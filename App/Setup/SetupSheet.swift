import AppKit
import Combine
import SwiftUI

/// First-run setup (spec 007 §6, 015 §3): Full Disk Access, then the admin helper.
struct SetupSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up TidyMyMac").font(.title2)
                    Text("Two permissions let TidyMyMac see and clean everything it offers. Nothing is removed without your review.")
                        .foregroundStyle(.secondary)
                }
            }
            step(1, done: app.fullDiskAccess == .granted, title: "Allow Full Disk Access",
                 detail: "Needed to size the Trash, sandboxed app caches and iPhone backups. System Settings › Privacy & Security › Full Disk Access, then turn on TidyMyMac.") {
                HStack {
                    Button("Open System Settings") { openFullDiskAccessSettings() }
                    Button("Reveal TidyMyMac in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                        .buttonStyle(.link)
                }
                if app.fullDiskAccess == .unknown {
                    Text("Can't tell whether it's on yet.").font(.caption).foregroundStyle(.secondary)
                }
            }
            step(2, done: app.helper.state.isReady, title: "Approve the admin helper",
                 detail: "A small helper that cleans system caches, logs and login items, and only acts on items it found itself. macOS asks you to allow it in Login Items; changes still need your password.") {
                switch app.helper.state {
                case .notInApplications:
                    Text("Move TidyMyMac to the Applications folder first, then open it from there.").foregroundStyle(.orange)
                case .needsApproval:
                    Button("Open Login Items Settings") { app.helper.openLoginItems() }
                case .needsAdminAccount:
                    Text("This is a standard account, and the helper only works for administrators. Everything in your own folders still works; system caches, logs and maintenance tasks need an admin account.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                case .broken(let why):
                    Text(why).font(.caption).foregroundStyle(.orange)
                    Button("Repair Helper") { Task { await app.helper.repair() } }
                case .ready:
                    EmptyView()
                default:
                    Button("Install Helper") { Task { await app.helper.install() } }
                        .disabled(app.fullDiskAccess != .granted && app.fullDiskAccess != .unknown)
                }
            }
            HStack {
                Spacer()
                Button("Later") { close() }
                Button("Get Started") { close() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!app.isSetUp)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onReceive(timer) { _ in app.refreshSetup() }
    }

    func close() {
        UserDefaults.standard.set(true, forKey: "setupDismissed")
        // Alerts need notification permission; asked once, after setup (spec 011 §4).
        app.status.requestNotificationPermission()
        dismiss()
    }

    @ViewBuilder
    func step<Actions: View>(_ n: Int, done: Bool, title: String, detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle")
                .font(.title2).foregroundStyle(done ? Color.green : Color.secondary)
                .accessibilityLabel(done ? "Step \(n), done" : "Step \(n)")
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !done { actions() }
            }
        }
    }

    /// Deep link with fallbacks (015 §3).
    func openFullDiskAccessSettings() {
        for s in ["x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
                  "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
                  "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"] {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }
}
