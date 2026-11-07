import RunLog
import SwiftUI

/// Health. In this build: run history and run detail with Restore (build spec §6.1–6.2).
/// Signals and reminders arrive in milestone 6 (spec 012).
struct HealthView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedRun: UUID?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Run History").font(.headline).padding([.horizontal, .top], 16).padding(.bottom, 8)
                if app.runs.isEmpty {
                    EmptyStateView(symbol: "clock.arrow.circlepath", message: "No runs yet. Every scan you clean or dry-run shows up here.")
                } else {
                    List(app.runs, id: \.header.runID, selection: $selectedRun) { run in RunRow(run: run) }
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
            if let run = app.runs.first(where: { $0.header.runID == selectedRun }) {
                RunDetail(run: run)
            } else {
                EmptyStateView(symbol: "heart.text.square", message: "Choose a run to see what went where.")
            }
        }
        .navigationSubtitle(app.runs.isEmpty ? "" : "\(app.runs.count) runs")
        .onAppear { app.reloadRuns() }
        .toolbar {
            Button { app.revealRunLogs() } label: { Label("Reveal Run Logs", systemImage: "folder") }
                .help("Show the run log files in Finder")
                .disabled(app.runs.isEmpty)
        }
    }
}

func moduleTitle(_ id: String) -> String {
    switch id {
    case "smartCare": "Smart Care"
    case "cleanup": "Cleanup"
    default: id.prefix(1).uppercased() + id.dropFirst()
    }
}

struct RunRow: View {
    let run: RunRecord

    var body: some View {
        let done = run.items.filter { $0.result == .done }
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(moduleTitle(run.header.module)).font(.headline)
                if run.header.dryRun { Text("Dry run").font(.caption).padding(.horizontal, 6).background(.quaternary, in: Capsule()) }
                if run.isInterrupted { Label("Interrupted", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
                Spacer()
                Text(sizeString(done.reduce(0) { $0 + $1.allocatedBytes })).monospacedDigit().foregroundStyle(.secondary)
            }
            Text("\(run.header.start.formatted(date: .abbreviated, time: .shortened)) · \(done.count) items")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct RunDetail: View {
    let run: RunRecord
    @Environment(AppModel.self) private var app
    @State private var refresh = 0

    var body: some View {
        let restorable = run.items.filter { app.restoreState($0) == .restored }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(moduleTitle(run.header.module) + (run.header.dryRun ? " (dry run)" : "")).font(.title2)
                    Text("Rule set \(run.header.ruleSetVersion) · TidyMyMac \(run.header.appVersion)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !run.header.dryRun {
                    Button("Restore All (\(restorable.count))") { app.restore(restorable); refresh += 1 }
                        .disabled(restorable.isEmpty)
                }
            }
            .padding(20)
            Table(run.items.enumerated().map { IndexedRunItem(id: $0.offset, item: $0.element) }, columns: {
                TableColumn("Item") { (row: IndexedRunItem) in let i = row.item;
                    VStack(alignment: .leading) {
                        Text((i.path as NSString).lastPathComponent).lineLimit(1)
                        PathText(path: i.path)
                    }
                }
                TableColumn("Rule") { (row: IndexedRunItem) in let i = row.item; Text(app.context?.rules.cleanRule(i.ruleID)?.title ?? i.ruleID).lineLimit(1) }
                TableColumn("Action") { (row: IndexedRunItem) in let i = row.item; Text(i.action.description) }.width(70)
                TableColumn("Result") { (row: IndexedRunItem) in let i = row.item;
                    Text(i.result.rawValue.capitalized).foregroundStyle(i.result == .done ? Color.primary : Color.orange)
                        .help(i.reason ?? "")
                }
                .width(70)
                TableColumn("Size") { (row: IndexedRunItem) in let i = row.item; Text(sizeString(i.allocatedBytes)).monospacedDigit() }.width(80)
                TableColumn("") { (row: IndexedRunItem) in let i = row.item;
                    if !run.header.dryRun, i.action == .trash, i.result == .done {
                        let state = app.restoreState(i)
                        if state == .restored {
                            Button("Restore") { app.restore([i]); refresh += 1 }
                        } else {
                            Text(state == .notInTrash ? "Not in Trash" : "—").foregroundStyle(.secondary).help(state.description)
                        }
                    }
                }
                .width(100)
            })
            .id(refresh)
        }
    }
}

struct IndexedRunItem: Identifiable {
    let id: Int
    let item: RunItem
}
