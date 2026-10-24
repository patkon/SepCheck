import SwiftUI
import AppKit

@main
struct SepCheckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppDelegate.model

    var body: some Scene {
        Window("SepCheck", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 800, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open …") {
                    NotificationCenter.default.post(name: .openPDF, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Separations") {
                Button("Show All") { model.soloIndex(0) }
                    .keyboardShortcut("0", modifiers: [])
                ForEach(1...9, id: \.self) { i in
                    Button {
                        model.soloIndex(i)
                    } label: {
                        if i <= model.channels.count {
                            Text("Only \(model.channels[i - 1].name)")
                        } else {
                            Text("Separation \(i)")
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(i)")), modifiers: [])
                    .disabled(i > model.channels.count)
                }
                Divider()
                Button("Process Colors Only") { model.showProcessOnly() }
                Button("Spot Colors Only") { model.showSpotsOnly() }
                Divider()
                Toggle("Single Separation in Black", isOn: $model.singleInBlack)
                    .keyboardShortcut("b", modifiers: [])
                Toggle("Ink Coverage Warning", isOn: $model.tacWarning)
                    .keyboardShortcut("t", modifiers: [])
            }
            CommandMenu("Page") {
                Button("Previous Page") { if model.page > 1 { model.page -= 1 } }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(model.page <= 1)
                Button("Next Page") { if model.page < model.pageCount { model.page += 1 } }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(model.page >= model.pageCount)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static let model = DocumentModel()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// PDF per Doppelklick / „Öffnen mit“ / Ziehen aufs Dock-Symbol
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return }
        Task { @MainActor in AppDelegate.model.open(url) }
    }
}
