import SwiftUI

/// Empty state: 48 pt symbol, one line, optional action (spec 007 §4, style guide §7).
struct EmptyStateView<Action: View>: View {
    let symbol: String
    let message: String
    @ViewBuilder var action: Action

    init(symbol: String, message: String, @ViewBuilder action: () -> Action = { EmptyView() }) {
        self.symbol = symbol
        self.message = message
        self.action = action()
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            action
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
