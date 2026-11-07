import SwiftUI

/// My Tools (spec 007 §2): a grid of 24 single-purpose tools. Each tile opens the module and tab
/// (or Cleanup category) that does that one job. It is a launcher, not a separate engine:
/// nothing here scans or removes anything on its own.
struct MyToolsView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""

    private var tools: [Tool] { Tool.all.filter { $0.matches(query) } }

    var body: some View {
        Group {
            if tools.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", message: "No tool matches \u{201C}\(query)\u{201D}.") {
                    Button("Show All Tools") { query = "" }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Each tool opens the part of a module that does just that one job, so you can skip the full scan.")
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 12)], spacing: 12) {
                            ForEach(tools) { tool in
                                ToolTile(tool: tool) { app.go(to: tool.destination) }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationSubtitle("\(Tool.all.count) single-purpose tools")
        .searchable(text: $query, placement: .toolbar, prompt: "Search tools")
    }
}

struct ToolTile: View {
    let tool: Tool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: tool.symbol)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                Text(tool.name).font(.headline).lineLimit(1)
                Text(tool.detail).font(.callout).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.background.secondary),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Opens \(tool.destination.module.title)")
        .accessibilityLabel(tool.name)
        .accessibilityHint("\(tool.detail). Opens \(tool.destination.module.title).")
    }
}
