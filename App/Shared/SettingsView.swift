import Monitors
import SwiftUI

/// Settings window (⌘,). Panes per build spec §6.11; the others arrive with later milestones.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("checkAppUpdatesAutomatically") private var checkUpdates = true
    @AppStorage(ClutterModel.minimumMBKey) private var duplicateMinimumMB = 1

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }

            AlertSettingsPane()
                .tabItem { Label("Alerts", systemImage: "exclamationmark.triangle") }

            Form { ReminderControls(status: app.status) }
                .formStyle(.grouped)
                .tabItem { Label("Reminders", systemImage: "bell") }

            VStack(spacing: 0) {
                IgnoreListView()
                Form {
                    Toggle("Check for app updates automatically", isOn: $checkUpdates)
                    Text("At most once a day, when Applications › Updates or Tidy Up opens. TidyMyMac never installs updates.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Duplicates: smallest file", selection: $duplicateMinimumMB) {
                        ForEach([1, 5, 10, 50, 100], id: \.self) { Text("\($0) MB").tag($0) }
                    }
                    LabeledContent("Hash cache") {
                        Button("Clear Hash Cache") { app.clutter.clearHashCache() }
                    }
                }
                .formStyle(.grouped)
                .frame(height: 200)
            }
            .tabItem { Label("Cleanup", systemImage: "bubbles.and.sparkles") }

            HelperSettings()
                .tabItem { Label("Helper", systemImage: "lock.shield") }
        }
        .frame(width: 560, height: 480)
    }
}

/// Settings › General (build spec §6.11).
struct GeneralSettings: View {
    @Environment(AppModel.self) private var app
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    var body: some View {
        Form {
            Toggle("Show in menu bar", isOn: $showInMenuBar)
            Toggle("Open at login", isOn: Binding(get: { app.loginItem.isOn }, set: { app.loginItem.set($0) }))
            if app.loginItem.needsApproval {
                HStack {
                    Text("Waiting for approval in Login Items.").font(.caption).foregroundStyle(.orange)
                    Button("Open Login Items Settings") { app.loginItem.openSettings() }.buttonStyle(.link).font(.caption)
                }
            }
            if let e = app.loginItem.error { Text(e).font(.caption).foregroundStyle(.orange) }
            LabeledContent("Run logs") {
                Button("Reveal Run Logs") { app.revealRunLogs() }.disabled(app.runs.isEmpty)
            }
            Text("Every run, including dry runs, is logged and kept.").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { app.loginItem.refresh() }
    }
}

/// Settings › Alerts: the low-disk and Trash lines are shared with Health (specs 011 §4, 012 §1).
struct AlertSettingsPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var status = app.status
        Form {
            Section {
                Picker("Low disk space below", selection: $status.lowDiskGB) {
                    ForEach(AlertSettings.lowDiskChoicesGB, id: \.self) { Text("\($0) GB").tag($0) }
                }
                Toggle("Alert me", isOn: $status.lowDiskAlertOn)
                Text("Health turns orange at the same line, and red below 10 GB.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Trash larger than", selection: $status.trashGB) {
                    ForEach(AlertSettings.trashChoicesGB, id: \.self) { Text("\($0) GB").tag($0) }
                }
                Toggle("Alert me", isOn: $status.trashAlertOn).disabled(app.fullDiskAccess != .granted)
                if app.fullDiskAccess != .granted {
                    HStack {
                        Text("Needs Full Disk Access").font(.caption).foregroundStyle(.secondary)
                        Button("Open Setup") { app.showSetup = true; app.showWindow() }.buttonStyle(.link).font(.caption)
                    }
                }
            }
            if status.notificationsDenied {
                HStack {
                    Label("Notifications are off in System Settings", systemImage: "bell.slash").font(.caption).foregroundStyle(.orange)
                    Button("Open") { status.openNotificationSettings() }.buttonStyle(.link).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Settings › Helper (build spec §6.11, 005 §4.4, 015 §5).
struct HelperSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            LabeledContent("Admin helper") { Text(app.helper.state.summary) }
            if case .broken(let why) = app.helper.state { Text(why).font(.caption).foregroundStyle(.orange) }
            HStack {
                switch app.helper.state {
                case .notInstalled: Button("Install Helper") { Task { await app.helper.install() } }
                case .needsApproval: Button("Open Login Items Settings") { app.helper.openLoginItems() }
                default: Button("Repair Helper") { Task { await app.helper.repair() } }
                }
                Button("Remove Helper") { Task { await app.helper.remove() } }
                    .disabled(app.helper.state == .notInstalled)
            }
            Text("Remove the helper before deleting TidyMyMac, so no stale Login Items entry is left behind.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Full Disk Access") { Text(app.fullDiskAccess == .granted ? "On" : (app.fullDiskAccess == .missing ? "Off" : "Can't tell")) }
            Button("Reset Full Disk Access Entry") { app.resetFullDiskAccess() }
                .help("Clears TidyMyMac's entry in Privacy & Security, for when the switch is on but access doesn't work")
        }
        .formStyle(.grouped)
        .onAppear { app.refreshSetup() }
    }
}
