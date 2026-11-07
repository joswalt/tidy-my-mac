import SwiftUI

/// Settings window (⌘,). Panes per build spec §6.11; the others arrive with later milestones.
struct SettingsView: View {
    @Environment(AppModel.self) private var app

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

            IgnoreListView()
                .tabItem { Label("Cleanup", systemImage: "bubbles.and.sparkles") }
        }
        .frame(width: 560, height: 380)
    }
}
