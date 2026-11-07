import SwiftUI

/// The app's three scenes (spec 016 §2): main window, menu bar extra and Settings.
/// Real file-system values are built in `CompositionRoot.swift` (spec 017 §2).
@main
struct TidyMyMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("TidyMyMac", id: MainWindow.id) {
            MainWindow()
                .environment(model)
        }
        .defaultSize(width: 1100, height: 720)

        MenuBarExtra("TidyMyMac", systemImage: "bubbles.and.sparkles") {
            MenuBarContent()
                .environment(model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
