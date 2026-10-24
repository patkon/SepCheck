import Foundation
import CoreGraphics
import ImageIO

/// Ein Farbauszug als 8-Bit-Ebene: 0 = kein Farbauftrag, 255 = 100 %.
final class InkPlane: @unchecked Sendable {
    let count: Int
    let ptr: UnsafeMutablePointer<UInt8>

    init(count: Int) {
        self.count = count
        ptr = .allocate(capacity: count)
        ptr.initialize(repeating: 0, count: count)
    }
    deinit { ptr.deallocate() }

    subscript(i: Int) -> UInt8 { ptr[i] }
}

/// Gesamtfarbauftrag pro Pixel in Prozent (z. B. 320 = 320 %)
final class TACPlane: @unchecked Sendable {
    let count: Int
    let ptr: UnsafeMutablePointer<UInt16>

    init(count: Int) {
        self.count = count
        ptr = .allocate(capacity: count)
        ptr.initialize(repeating: 0, count: count)
    }
    deinit { ptr.deallocate() }

    subscript(i: Int) -> UInt16 { ptr[i] }
}

struct InkColor: Sendable {
    var r: Float, g: Float, b: Float
}

struct Channel: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let isProcess: Bool
    let color: InkColor
    let plane: InkPlane
}

struct RenderedPage: Sendable {
    let width: Int
    let height: Int
    let dpi: Int
    let channels: [Channel]
    let tac: TACPlane
    let maxTAC: Int

    /// Farbwerte (0–100 %) aller Kanäle an einer Pixelposition
    func values(x: Int, y: Int) -> (perChannel: [String: Int], total: Int)? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let i = y * width + x
        var dict: [String: Int] = [:]
        for c in channels { dict[c.name] = (Int(c.plane[i]) * 100 + 127) / 255 }
        return (dict, Int(tac[i]))
    }
}

enum GSError: LocalizedError {
    case notFound
    case failed(String)
    case noOutput

    var errorDescription: String? {
        switch self {
        case .notFound:
            return String(localized: "Ghostscript was not found.\nInstall it in Terminal with:  brew install ghostscript")
        case .failed(let msg):
            return String(localized: "Ghostscript error:\n\(msg)")
        case .noOutput:
            return String(localized: "Ghostscript did not produce any separations.")
        }
    }
}

enum Ghostscript {
    static let processOrder = ["Cyan", "Magenta", "Yellow", "Black"]

    /// Näherungsfarben der Prozessfarben für die Bildschirmdarstellung
    static let processColors: [String: InkColor] = [
        "Cyan":    InkColor(r: 0.00, g: 0.68, b: 0.94),
        "Magenta": InkColor(r: 0.93, g: 0.00, b: 0.55),
        "Yellow":  InkColor(r: 1.00, g: 0.95, b: 0.00),
        "Black":   InkColor(r: 0.14, g: 0.12, b: 0.13),
    ]

    static func findExecutable() -> String? {
        ["/opt/homebrew/bin/gs", "/usr/local/bin/gs", "/opt/local/bin/gs", "/usr/bin/gs"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Rendert eine Seite mit dem tiffsep-Device (inkl. Überdrucken) in Einzelauszüge.
    static func render(pdf: URL, page: Int, dpi: Int) throws -> RenderedPage {
        guard let gs = findExecutable() else { throw GSError.notFound }

        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("sepcheck-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gs)
        process.arguments = [
            "-q", "-dNOPAUSE", "-dBATCH", "-dSAFER",
            "-sDEVICE=tiffsep",
            "-dPrintSpotCMYK",               // gibt CMYK-Ersatzwerte der Sonderfarben aus
            "-r\(dpi * 2)", "-dDownScaleFactor=2", // Kantenglättung
            "-dFirstPage=\(page)", "-dLastPage=\(page)",
            "-sOutputFile=\(dir.path)/p.tif",
            pdf.path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let outData = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: outData, as: UTF8.self)

        if process.terminationStatus != 0 {
            throw GSError.failed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Sonderfarben-Ersatzwerte parsen:  %%SeparationColor: "PANTONE 185 C" 100% ink = 0 29484 26208 0 CMYK
        var spotOrder: [String] = []
        var spotCMYK: [String: [Float]] = [:]
        for line in output.split(separator: "\n") where line.hasPrefix("%%SeparationColor:") {
            guard let q1 = line.firstIndex(of: "\""),
                  let q2 = line[line.index(after: q1)...].firstIndex(of: "\""),
                  let eq = line.range(of: "=") else { continue }
            let name = String(line[line.index(after: q1)..<q2])
            let nums = line[eq.upperBound...].split(separator: " ").compactMap { Float($0) }
            guard nums.count >= 4 else { continue }
            spotOrder.append(name)
            spotCMYK[name] = nums.prefix(4).map { min(1, $0 / 32768) }
        }

        // Auszugsdateien einsammeln: p(Name).tif
        let files = try fm.contentsOfDirectory(atPath: dir.path)
        var planes: [String: (w: Int, h: Int, plane: InkPlane)] = [:]
        for f in files where f.hasPrefix("p(") && f.hasSuffix(").tif") {
            let name = String(f.dropFirst(2).dropLast(5))
            if let loaded = loadInk(url: dir.appendingPathComponent(f)) {
                planes[name] = loaded
            }
        }
        guard let first = planes.values.first else { throw GSError.noOutput }
        let w = first.w, h = first.h

        // Reihenfolge: C, M, Y, K, dann Sonderfarben
        let spotNames = spotOrder.filter { planes[$0] != nil }
            + planes.keys.filter { !processOrder.contains($0) && !spotOrder.contains($0) }.sorted()
        let ordered = processOrder.filter { planes[$0] != nil } + spotNames

        var channels: [Channel] = []
        for name in ordered {
            guard let p = planes[name], p.w == w, p.h == h else { continue }
            let isProcess = processOrder.contains(name)
            let color = isProcess
                ? processColors[name]!
                : (spotCMYK[name].map(cmykToRGB) ?? InkColor(r: 1, g: 0.5, b: 0))
            channels.append(Channel(name: name, isProcess: isProcess, color: color, plane: p.plane))
        }

        // Gesamtfarbauftrag berechnen
        let n = w * h
        let tac = TACPlane(count: n)
        let t = tac.ptr
        var maxSum = 0
        for c in channels {
            let src = c.plane.ptr
            for i in 0..<n { t[i] &+= UInt16(src[i]) }
        }
        for i in 0..<n {
            let pct = (Int(t[i]) * 100 + 127) / 255
            t[i] = UInt16(pct)
            if pct > maxSum { maxSum = pct }
        }

        return RenderedPage(width: w, height: h, dpi: dpi, channels: channels, tac: tac, maxTAC: maxSum)
    }

    /// Lädt ein Graustufen-TIFF von tiffsep (weiß = keine Farbe) und invertiert es zu Farbauftrag.
    private static func loadInk(url: URL) -> (w: Int, h: Int, plane: InkPlane)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = img.width, h = img.height
        let plane = InkPlane(count: w * h)

        // Bevorzugt: Rohdaten ohne Farbmanagement übernehmen
        if img.bitsPerComponent == 8, img.bitsPerPixel == 8,
           let data = img.dataProvider?.data, let bytes = CFDataGetBytePtr(data) {
            let bpr = img.bytesPerRow
            for y in 0..<h {
                let row = bytes + y * bpr
                let dst = plane.ptr + y * w
                for x in 0..<w { dst[x] = 255 &- row[x] }
            }
            return (w, h, plane)
        }

        // Fallback: in Graustufen-Kontext zeichnen
        guard let ctx = CGContext(data: plane.ptr, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        for i in 0..<(w * h) { plane.ptr[i] = 255 &- plane.ptr[i] }
        return (w, h, plane)
    }

    /// Einfache multiplikative Näherung CMYK → RGB über die Prozessfarben
    static func cmykToRGB(_ v: [Float]) -> InkColor {
        var r: Float = 1, g: Float = 1, b: Float = 1
        for (i, name) in processOrder.enumerated() {
            let a = v[i]
            let c = processColors[name]!
            r *= 1 - a * (1 - c.r)
            g *= 1 - a * (1 - c.g)
            b *= 1 - a * (1 - c.b)
        }
        return InkColor(r: r, g: g, b: b)
    }

    /// Setzt die sichtbaren Auszüge zu einem RGB-Vorschaubild zusammen.
    static func composite(_ page: RenderedPage, visible: Set<String>, singleInBlack: Bool,
                          tacLimit: Int?) -> CGImage? {
        let w = page.width, h = page.height, n = w * h
        var chans = page.channels.filter { visible.contains($0.name) }
        if singleInBlack && chans.count == 1 {
            let c = chans[0]
            chans = [Channel(name: c.name, isProcess: c.isProcess,
                             color: InkColor(r: 0, g: 0, b: 0), plane: c.plane)]
        }
        let ptrs = chans.map { $0.plane.ptr }
        let cols = chans.map { $0.color }
        let k = chans.count
        let limit = tacLimit.map { UInt16(clamping: $0) } ?? UInt16.max
        let t = page.tac.ptr

        var out = [UInt8](repeating: 255, count: n * 4)
        out.withUnsafeMutableBufferPointer { o in
            for i in 0..<n {
                if t[i] > limit {
                    o[i * 4] = 0; o[i * 4 + 1] = 230; o[i * 4 + 2] = 60
                    continue
                }
                var r: Float = 1, g: Float = 1, b: Float = 1
                for j in 0..<k {
                    let v = ptrs[j][i]
                    if v == 0 { continue }
                    let a = Float(v) * (1.0 / 255.0)
                    let c = cols[j]
                    r *= 1 - a * (1 - c.r)
                    g *= 1 - a * (1 - c.g)
                    b *= 1 - a * (1 - c.b)
                }
                o[i * 4] = UInt8(r * 255 + 0.5)
                o[i * 4 + 1] = UInt8(g * 255 + 0.5)
                o[i * 4 + 2] = UInt8(b * 255 + 0.5)
            }
        }

        guard let provider = CGDataProvider(data: Data(out) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
