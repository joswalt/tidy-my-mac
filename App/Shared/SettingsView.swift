import SwiftUI

/// Settings window (⌘,). Panes per build spec §6.11; filled in by later milestones.
struct SettingsView: View {
    var body: some View {
        TabView {
            EmptyStateView(symbol: "gearshape", message: "General settings arrive in a later build.")
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 260)
    }
}
