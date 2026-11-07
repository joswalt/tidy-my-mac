import SwiftUI

/// The app's three scenes (spec 016 §2): main window, menu bar extra and Settings.
/// This file is also the composition root: the only place in the app allowed to build
/// real file-system values such as `Home` (spec 017 §2).
@main
struct TidyMyMacApp: App {
    var body: some Scene {
        WindowGroup("TidyMyMac", id: MainWindow.id) {
            MainWindow()
        }
        .defaultSize(width: 1100, height: 720)

        MenuBarExtra("TidyMyMac", systemImage: "bubbles.and.sparkles") {
            MenuBarContent()
        }

        Settings {
            SettingsView()
        }
    }
}
