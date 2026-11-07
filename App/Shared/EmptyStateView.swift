import SwiftUI

/// Empty state: 48 pt symbol, one line, optional action (spec 007 §4, style guide §7).
struct EmptyStateView: View {
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

/// Placeholder shown by every module until its milestone lands.
struct ModulePlaceholder: View {
    let module: SidebarModule

    var body: some View {
        EmptyStateView(symbol: module.symbol, message: "\(module.title) isn't built yet.")
    }
}
