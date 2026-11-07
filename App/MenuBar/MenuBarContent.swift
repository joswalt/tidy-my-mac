import SwiftUI

/// Menu bar extra contents. Monitors and alerts arrive in milestone 6 (spec 011);
/// the glyph becomes a template version of the Sweep icon then.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open TidyMyMac") {
            openWindow(id: MainWindow.id)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit TidyMyMac") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
