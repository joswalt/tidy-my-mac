import AppKit
import RuleEngine
import SwiftUI

func sizeString(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

/// Safe / Caution / Risky with a symbol and a word, never colour alone (style guide §3).
struct RiskBadge: View {
    let risk: RuleRisk

    var body: some View {
        let (text, symbol, color): (String, String, Color) = switch risk {
        case .safe: ("Safe", "checkmark.circle.fill", .green)
        case .caution: ("Caution", "exclamationmark.triangle.fill", .orange)
        case .risky: ("Risky", "xmark.octagon.fill", .red)
        }
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
    }
}

/// "Trash" in secondary, or "Delete" with a flame in red (spec 007 §4).
struct DestinationLabel: View {
    let action: RuleAction

    var body: some View {
        if action == .delete {
            Label("Delete", systemImage: "flame").font(.caption).foregroundStyle(.red)
        } else {
            Label("Trash", systemImage: "trash").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A checkbox that can show a mixed state for groups.
struct TriStateBox: View {
    let state: Selection.GroupState
    let action: () -> Void

    var symbol: String {
        switch state {
        case .all: "checkmark.square.fill"
        case .some: "minus.square.fill"
        case .none: "square"
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
            .foregroundStyle(state == .none ? Color.secondary : Color.accentColor)
            .font(.body)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .all ? "Untick all" : "Tick all")
    }
}

/// Footer bar: live summary left, actions right (spec 007 §1).
struct FooterBar<Buttons: View>: View {
    let summary: String
    @ViewBuilder let buttons: Buttons

    var body: some View {
        HStack(spacing: 12) {
            Text(summary)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Spacer()
            buttons
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Path text: monospaced, truncated in the middle.
struct PathText: View {
    let path: String
    var body: some View {
        Text(path).font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            .help(path)
    }
}

/// The table of items for one or more rules, with ticks.
struct ItemTable: View {
    @Bindable var session: ScanSession
    let items: [Candidate]
    @Environment(AppModel.self) private var app

    var body: some View {
        Table(items) {
            TableColumn("") { c in
                Toggle("", isOn: Binding(get: { session.selection.contains(c) }, set: { session.selection.set(c, $0) }))
                    .labelsHidden()
                    .accessibilityLabel("Select \(c.name)")
            }
            .width(24)
            TableColumn("Name") { c in Text(c.name).lineLimit(1).help(c.name) }.width(min: 140, ideal: 220)
            TableColumn("Location") { c in PathText(path: (c.path as NSString).deletingLastPathComponent) }
            TableColumn("Risk") { c in RiskBadge(risk: c.risk) }.width(80)
            TableColumn("Goes to") { c in DestinationLabel(action: c.action) }.width(70)
            TableColumn("Size") { c in
                Text(sizeString(c.allocatedBytes)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(80)
        }
        .contextMenu(forSelectionType: Candidate.ID.self) { ids in
            if let c = items.first(where: { ids.contains($0.id) }) {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: c.path)]) }
                Button("Ignore") { app.ignore(.init(kind: .path, value: c.path)) }
            }
        }
    }
}

/// Short-lived confirmation message (spec 007 §4 toasts).
struct ToastOverlay: ViewModifier {
    let message: String?
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 70)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: message)
    }
}

/// The one confirmation before any removal (spec 007 §3.5): count, size and destination.
struct CleanConfirm: ViewModifier {
    @Binding var isPresented: Bool
    let summary: CleanupSummary
    /// Items removed with administrator rights are named one by one (not just counted).
    var adminItems: [Candidate] = []
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert("Clean \(summary.itemCount.formatted()) \(summary.itemCount == 1 ? "item" : "items")?", isPresented: $isPresented) {
            Button(buttonTitle, role: summary.trashBytes == 0 ? .destructive : nil, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message)
        }
    }

    var buttonTitle: String {
        summary.trashBytes == 0 ? "Delete \(sizeString(summary.deleteBytes))" : "Clean \(sizeString(summary.totalBytes))"
    }

    var message: String {
        var lines: [String] = []
        if summary.trashBytes > 0 { lines.append("\(sizeString(summary.trashBytes)) moves to the Trash, where you can restore it.") }
        if summary.deleteBytes > 0 { lines.append("\(sizeString(summary.deleteBytes)) of caches and logs is deleted permanently.") }
        if !adminItems.isEmpty {
            let names = adminItems.prefix(12).map { "• " + $0.path }
            let more = adminItems.count > 12 ? ["…and \(adminItems.count - 12) more"] : []
            lines.append("\nWith your administrator password:\n" + (names + more).joined(separator: "\n") + "\n")
        }
        lines.append("Every item is logged in Health › Run History.")
        return lines.joined(separator: " ")
    }
}

extension View {
    func cleanConfirm(_ isPresented: Binding<Bool>, summary: CleanupSummary, adminItems: [Candidate] = [], onConfirm: @escaping () -> Void) -> some View {
        modifier(CleanConfirm(isPresented: isPresented, summary: summary, adminItems: adminItems, onConfirm: onConfirm))
    }

    func toast(_ message: String?) -> some View { modifier(ToastOverlay(message: message)) }
}

/// What a finished run did, or what a dry run would have done.
struct RunResultView: View {
    let run: CleanupEngine.Run
    let dryRun: Bool
    let onDone: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let done = run.outcome.done
        let trash = done.filter { $0.action == .trash }.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        let total = done.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        VStack(spacing: 14) {
            Image(systemName: dryRun ? "doc.text.magnifyingglass" : "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(dryRun ? Color.secondary : Color.green)
            Text(dryRun ? "Dry run: nothing was changed" : "Freed \(sizeString(total))")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(dryRun
                 ? "\(done.count) items would be removed (\(sizeString(total))). The list is in Health › Run History."
                 : "\(sizeString(trash)) is in the Trash and can be restored from Health › Run History.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !run.outcome.skipped.isEmpty || !run.outcome.failed.isEmpty {
                Text("\(run.outcome.skipped.count) skipped and \(run.outcome.failed.count) failed; the reasons are in the run log.")
                    .font(.callout).foregroundStyle(.orange)
            }
            HStack {
                Button("View Run Log") { app.healthTab = .history; app.selectedModule = .health }
                Button("Done", action: onDone).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The one confirmation before hand-picked items move (My Clutter, Space Lens): count, size and
/// destination. These never delete; everything goes to the Trash (spec 014 §5, build spec §6.6–6.8).
struct TrashConfirm: ViewModifier {
    @Binding var isPresented: Bool
    let count: Int
    let bytes: Int64
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert("Move \(count.formatted()) \(count == 1 ? "item" : "items") to the Trash?", isPresented: $isPresented) {
            Button("Move \(sizeString(bytes)) to Trash", action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(sizeString(bytes)) moves to the Trash, where you can restore it. Nothing is deleted. Every item is logged in Health › Run History.")
        }
    }
}

extension View {
    func trashConfirm(_ isPresented: Binding<Bool>, count: Int, bytes: Int64, onConfirm: @escaping () -> Void) -> some View {
        modifier(TrashConfirm(isPresented: isPresented, count: count, bytes: bytes, onConfirm: onConfirm))
    }
}

/// A flag a detached scan polls to stop early.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
