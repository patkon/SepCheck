import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: DocumentModel
    @State private var showImporter = false

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 360)
        } detail: {
            CanvasView(model: model)
        }
        .navigationTitle(model.url?.lastPathComponent ?? "SepCheck")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { showImporter = true } label: {
                    Label("Open", systemImage: "folder")
                }
                .help("Open PDF (⌘O)")
            }
            ToolbarItemGroup {
                if model.pageCount > 1 {
                    Button { model.page -= 1 } label: { Image(systemName: "chevron.left") }
                        .disabled(model.page <= 1)
                        .help("Previous Page")
                    Text("Page \(model.page) / \(model.pageCount)")
                        .monospacedDigit()
                        .frame(minWidth: 90)
                    Button { model.page += 1 } label: { Image(systemName: "chevron.right") }
                        .disabled(model.page >= model.pageCount)
                        .help("Next Page")
                }
                Picker("Resolution", selection: $model.dpi) {
                    Text("72 dpi").tag(72)
                    Text("150 dpi").tag(150)
                    Text("300 dpi").tag(300)
                    Text("600 dpi").tag(600)
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                .help("Render resolution – higher = finer detail, slower")
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { model.open(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPDF)) { _ in
            showImporter = true
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return false }
            model.open(url)
            return true
        }
    }
}

// MARK: - Seitenleiste

struct SidebarView: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        VStack(spacing: 0) {
            List {
                if !model.channels.isEmpty {
                    let process = model.channels.filter(\.isProcess)
                    let spots = model.channels.filter { !$0.isProcess }

                    Section("Process Colors") {
                        ForEach(process) { ch in row(ch) }
                    }
                    if !spots.isEmpty {
                        Section("Spot Colors (\(spots.count))") {
                            ForEach(spots) { ch in row(ch) }
                        }
                    }
                } else if !model.isRendering {
                    Text("No file open")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)

            if model.rendered != nil {
                Divider()
                controls.padding(12)
            }
        }
    }

    private func row(_ ch: Channel) -> some View {
        let index = (model.channels.firstIndex { $0.name == ch.name } ?? 0) + 1
        let on = model.visible.contains(ch.name)
        let isSolo = model.visible == [ch.name]

        return HStack(spacing: 8) {
            Button { model.toggle(ch.name) } label: {
                Image(systemName: on ? "eye" : "eye.slash")
                    .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help("Show/hide")

            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: Double(ch.color.r), green: Double(ch.color.g), blue: Double(ch.color.b)))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.2)))
                .frame(width: 16, height: 16)

            Text(ch.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))

            Spacer(minLength: 4)

            if let v = model.hover?.perChannel[ch.name] {
                Text("\(v) %")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Button { model.solo(ch.name) } label: {
                Text(index <= 9 ? "\(index)" : "S")
                    .font(.caption.weight(.semibold))
                    .frame(width: 18, height: 18)
                    .background(isSolo ? Color.accentColor : Color.secondary.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(isSolo ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .help(index <= 9 ? String(localized: "Show only this separation (key \(index))")
                               : String(localized: "Show only this separation"))
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.solo(ch.name) }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("All") { model.showAll() }
                Button("CMYK") { model.showProcessOnly() }
                Button("Spots") { model.showSpotsOnly() }
                    .disabled(!model.channels.contains { !$0.isProcess })
            }
            .controlSize(.small)

            Toggle("Single Separation in Black", isOn: $model.singleInBlack)
                .controlSize(.small)

            Divider()

            if let r = model.rendered {
                let over = r.maxTAC > model.tacLimit
                HStack {
                    Text("Max. Ink Coverage")
                    Spacer()
                    Text("\(r.maxTAC) %")
                        .monospacedDigit()
                        .fontWeight(.semibold)
                        .foregroundStyle(over ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                }
                if let h = model.hover {
                    HStack {
                        Text("Under Pointer")
                        Spacer()
                        Text("\(h.total) %")
                            .monospacedDigit()
                            .foregroundStyle(h.total > model.tacLimit ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                    }
                }
            }

            Toggle(isOn: $model.tacWarning) {
                Text("Mark areas over limit in green")
            }
            .controlSize(.small)

            Stepper(value: $model.tacLimit, in: 200...400, step: 10) {
                Text("Limit: \(model.tacLimit) %").monospacedDigit()
            }
            .controlSize(.small)
        }
        .font(.callout)
    }
}

// MARK: - Arbeitsfläche

struct CanvasView: View {
    @ObservedObject var model: DocumentModel
    @State private var zoom: CGFloat = 1
    @State private var fit = true
    @State private var pinchBase: CGFloat?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(nsColor: .underPageBackgroundColor).ignoresSafeArea()

                if let img = model.image {
                    let w = CGFloat(img.width), h = CGFloat(img.height)
                    let fitZoom = max(0.01, min((geo.size.width - 40) / w, (geo.size.height - 40) / h))
                    let z = fit ? fitZoom : zoom

                    ScrollView([.horizontal, .vertical]) {
                        Image(decorative: img, scale: 1)
                            .resizable()
                            .interpolation(z >= 2 ? .none : .high)
                            .frame(width: w * z, height: h * z)
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                            .onContinuousHover(coordinateSpace: .local) { phase in
                                switch phase {
                                case .active(let p):
                                    model.updateHover(pixelX: Int(p.x / z), pixelY: Int(p.y / z))
                                case .ended:
                                    model.hover = nil
                                }
                            }
                            .padding(20)
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                    }
                    .gesture(
                        MagnifyGesture()
                            .onChanged { v in
                                let base = pinchBase ?? z
                                pinchBase = base
                                fit = false
                                zoom = min(32, max(0.05, base * v.magnification))
                            }
                            .onEnded { _ in pinchBase = nil }
                    )
                    .overlay(alignment: .bottomTrailing) {
                        zoomControls(current: z, fitZoom: fitZoom)
                            .padding(12)
                    }
                } else if model.url == nil {
                    emptyState
                }

                if model.isRendering {
                    ProgressView("Computing separations …")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                if let err = model.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(err)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                    .padding(24)
                    .frame(maxWidth: 460)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.down.right")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop PDF here")
                .font(.title2)
            Text("or open with ⌘O")
                .foregroundStyle(.secondary)
            if Ghostscript.findExecutable() == nil {
                Text(GSError.notFound.localizedDescription)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(.top, 8)
            }
        }
    }

    private func zoomControls(current z: CGFloat, fitZoom: CGFloat) -> some View {
        // 100 % = Originalgröße im Druck (Pixel bei gewählter dpi → Punkte)
        let printScale = 72 / CGFloat(model.dpi)
        let percent = Int((z / printScale * 100).rounded())

        return HStack(spacing: 6) {
            Button { setZoom(z / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                .keyboardShortcut("-", modifiers: .command)
            Text("\(percent) %")
                .monospacedDigit()
                .frame(minWidth: 52)
            Button { setZoom(z * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                .keyboardShortcut("+", modifiers: .command)
            Divider().frame(height: 16)
            Button("Fit") { fit = true }
                .keyboardShortcut("0", modifiers: .command)
            Button("100 %") { setZoom(printScale) }
                .keyboardShortcut("1", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    private func setZoom(_ z: CGFloat) {
        fit = false
        zoom = min(32, max(0.05, z))
    }
}

extension Notification.Name {
    static let openPDF = Notification.Name("SepCheck.openPDF")
}
