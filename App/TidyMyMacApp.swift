import SwiftUI

/// The app's three scenes (spec 016 §2): main window, menu bar extra and Settings.
/// Real file-system values are built in `CompositionRoot.swift` (spec 017 §2).
@main
struct TidyMyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    var body: some Scene {
        Window("TidyMyMac", id: MainWindow.id) {
            MainWindow()
                .environment(model)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1100, height: 720)

        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarContent()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Dock icon policy (spec 011 §1): closing the main window leaves the app in the menu bar only
/// (accessory); opening it brings the Dock icon back.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            // Delivered on the main queue; the window is only read there.
            nonisolated(unsafe) let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                if let w = window, Self.isMain(w), NSApp.activationPolicy() != .regular {
                    NSApp.setActivationPolicy(.regular)
                }
            }
        }
        nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            nonisolated(unsafe) let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let w = window, Self.isMain(w),
                      UserDefaults.standard.bool(forKey: "showInMenuBar") else { return }
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    static func isMain(_ w: NSWindow) -> Bool {
        !(w is NSPanel) && (w.identifier?.rawValue.hasPrefix(MainWindow.id) ?? false)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { model?.showWindow() }
        return true
    }
}
