import SwiftUI

/// Settings window (⌘,). Panes per build spec §6.11; the others arrive with later milestones.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("checkAppUpdatesAutomatically") private var checkUpdates = true
    @AppStorage(ClutterModel.minimumMBKey) private var duplicateMinimumMB = 1

    var body: some View {
        TabView {
            Form {
                LabeledContent("Run logs") {
                    Button("Reveal Run Logs") { app.revealRunLogs() }.disabled(app.runs.isEmpty)
                }
                Text("Every run, including dry runs, is logged and kept.").font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            VStack(spacing: 0) {
                IgnoreListView()
                Form {
                    Toggle("Check for app updates automatically", isOn: $checkUpdates)
                    Text("At most once a day, when Applications › Updates or Smart Care opens. TidyMyMac never installs updates.")
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
