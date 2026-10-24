import Foundation
import CoreGraphics
import SwiftUI

@MainActor
final class DocumentModel: ObservableObject {
    @Published var url: URL?
    @Published var pageCount = 0
    @Published var page = 1 { didSet { if page != oldValue { render() } } }
    @Published var dpi = 150 { didSet { if dpi != oldValue { render() } } }

    @Published private(set) var rendered: RenderedPage?
    @Published private(set) var image: CGImage?
    @Published private(set) var isRendering = false
    @Published var errorMessage: String?

    @Published var visible: Set<String> = [] { didSet { recomposite() } }
    @Published var singleInBlack = false { didSet { recomposite() } }
    @Published var tacWarning = false { didSet { recomposite() } }
    @Published var tacLimit = 300 { didSet { if tacWarning { recomposite() } } }

    /// Werte unter dem Mauszeiger
    @Published var hover: (perChannel: [String: Int], total: Int)?

    private var renderTask: Task<Void, Never>?
    private var compositeTask: Task<Void, Never>?
    private var renderGeneration = 0

    var channels: [Channel] { rendered?.channels ?? [] }

    func open(_ url: URL) {
        guard let doc = CGPDFDocument(url as CFURL) else {
            errorMessage = String(localized: "The file could not be opened as a PDF.")
            return
        }
        self.url = url
        pageCount = doc.numberOfPages
        rendered = nil
        image = nil
        visible = []
        if page != 1 { page = 1 } else { render() }
    }

    func render() {
        guard let url else { return }
        renderTask?.cancel()
        renderGeneration += 1
        let gen = renderGeneration
        let page = self.page, dpi = self.dpi
        isRendering = true
        errorMessage = nil

        renderTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try Ghostscript.render(pdf: url, page: page, dpi: dpi) }
            }.value
            guard gen == self.renderGeneration else { return }
            self.isRendering = false
            switch result {
            case .success(let r):
                let names = Set(r.channels.map(\.name))
                // Sichtbarkeit beim Seitenwechsel beibehalten, neue Kanäle einblenden
                let previous = Set(self.channels.map(\.name))
                let keep = self.visible.intersection(names)
                let added = names.subtracting(previous)
                self.rendered = r
                self.visible = previous.isEmpty ? names : keep.union(added)
            case .failure(let e):
                self.errorMessage = e.localizedDescription
            }
        }
    }

    func recomposite() {
        guard let r = rendered else { image = nil; return }
        compositeTask?.cancel()
        let vis = visible, single = singleInBlack
        let limit = tacWarning ? tacLimit : nil
        compositeTask = Task {
            let img = await Task.detached(priority: .userInitiated) {
                Ghostscript.composite(r, visible: vis, singleInBlack: single, tacLimit: limit)
            }.value
            if !Task.isCancelled { self.image = img }
        }
    }

    // MARK: - Kanalsteuerung

    func toggle(_ name: String) {
        if visible.contains(name) { visible.remove(name) } else { visible.insert(name) }
    }

    /// Nur diesen Kanal zeigen – erneuter Klick zeigt wieder alle
    func solo(_ name: String) {
        if visible == [name] { visible = Set(channels.map(\.name)) } else { visible = [name] }
    }

    func showAll() { visible = Set(channels.map(\.name)) }
    func showProcessOnly() { visible = Set(channels.filter(\.isProcess).map(\.name)) }
    func showSpotsOnly() { visible = Set(channels.filter { !$0.isProcess }.map(\.name)) }

    /// Kanal per Nummerntaste (1 = erster Kanal) solo schalten, 0 = alle
    func soloIndex(_ i: Int) {
        if i == 0 { showAll(); return }
        guard i - 1 < channels.count else { return }
        solo(channels[i - 1].name)
    }

    func updateHover(pixelX: Int, pixelY: Int) {
        hover = rendered?.values(x: pixelX, y: pixelY)
    }
}
