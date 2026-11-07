import AppKit
import RuleEngine
import SwiftUI

/// Cleanup: category list + rule detail + item table, footer with Dry Run / Review / Clean (spec 007 §2).
struct CleanupView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedRule: String?
    @State private var showReview = false
    @State private var showConfirm = false
    @State private var showIgnoreList = false

    var session: ScanSession { app.cleanup }

    var body: some View {
        @Bindable var session = session
        VStack(spacing: 0) {
            switch session.phase {
            case .idle:
                EmptyStateView(symbol: "bubbles.and.sparkles", message: "Scan to see caches, logs and other junk you can remove.") {
                    Button("Scan") { session.scan() }.buttonStyle(.borderedProminent).controlSize(.large)
                }
            case .scanning:
                ScanningView(session: session)
            case .running:
                ProgressView("Cleaning…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done(let dry):
                if let run = session.lastRun { RunResultView(run: run, dryRun: dry) { session.finish() } }
            case .results:
                results(session)
            }
        }
        .navigationSubtitle(session.report.map { "\(sizeString($0.totalBytes)) found" } ?? "")
        .toolbar {
            ToolbarItemGroup {
                Button { showIgnoreList = true } label: { Label("Ignore List", systemImage: "eye.slash") }
                    .help("Items and categories you've chosen to ignore")
                Button { session.scan() } label: { Label("Scan Again", systemImage: "arrow.clockwise") }
                    .help("Scan again (⌘R)")
                    .keyboardShortcut("r")
                    .disabled(session.phase == .scanning || session.phase == .running)
            }
        }
        .sheet(isPresented: $showReview) { ReviewSheet(session: session, onDryRun: { session.run(dryRun: true) }) { showConfirm = true } }
        .sheet(isPresented: $showIgnoreList) { IgnoreListView().frame(minWidth: 560, minHeight: 360) }
        .cleanConfirm($showConfirm, summary: session.summary, adminItems: session.selected.filter(\.viaHelper)) { session.run(dryRun: false) }
    }

    @ViewBuilder
    func results(_ session: ScanSession) -> some View {
        let results = session.report?.results ?? []
        HSplitView {
            List(selection: $selectedRule) {
                ForEach(results, id: \.rule.id) { r in
                    CategoryRow(session: session, result: r).tag(r.rule.id)
                }
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            if let r = results.first(where: { $0.rule.id == selectedRule }) ?? results.first {
                RuleDetail(session: session, result: r)
            }
        }
        .onAppear {
            if let focus = app.cleanupFocus, !results.isEmpty {
                // A category this scan doesn't have (e.g. a rule that is off) falls back to the first one.
                if results.contains(where: { $0.rule.id == focus }) { selectedRule = focus }
                app.cleanupFocus = nil
            }
            if selectedRule == nil { selectedRule = results.first(where: { !$0.candidates.isEmpty })?.rule.id }
        }
        .onChange(of: results.map(\.rule.id)) { _, ids in
            if let focus = app.cleanupFocus, ids.contains(focus) { selectedRule = focus; app.cleanupFocus = nil }
        }
        FooterBar(summary: session.summary.line) {
            Button("Dry Run") { session.run(dryRun: true) }
                .help("List exactly what would be removed, without changing anything")
                .disabled(session.summary.itemCount == 0)
            Button("Review…") { showReview = true }.disabled(session.candidates.isEmpty)
            Button(session.summary.itemCount == 0 ? "Clean" : "Clean \(sizeString(session.summary.totalBytes))") { showConfirm = true }
                .buttonStyle(.borderedProminent)
                .disabled(session.summary.itemCount == 0)
        }
    }
}

struct CategoryRow: View {
    @Bindable var session: ScanSession
    let result: RuleScanResult

    var body: some View {
        HStack(spacing: 8) {
            if result.rule.risk == .risky || result.candidates.isEmpty {
                Image(systemName: result.rule.risk == .risky ? "hand.raised" : "square").foregroundStyle(.tertiary)
                    .help(result.rule.risk == .risky ? "Risky items are ticked one by one" : "Nothing found")
                    .accessibilityLabel(result.rule.risk == .risky ? "Risky items are ticked one by one" : "Nothing to tick")
            } else {
                TriStateBox(state: session.selection.state(of: result.candidates), name: result.rule.title) {
                    session.selection.setGroup(result.candidates, session.selection.state(of: result.candidates) != .all)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(result.rule.title)
                if let note = stateNote { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if !result.candidates.isEmpty {
                Text(sizeString(result.totalBytes)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .opacity(stateNote == nil ? 1 : 0.6)
    }

    var stateNote: String? {
        switch result.state {
        case .scanned: result.candidates.isEmpty ? "Nothing found" : nil
        case .needsFullDiskAccess: "Needs Full Disk Access"
        case .requiresHelper: "Needs the admin helper"
        case .notForThisMacOS: "Not for this version of macOS"
        case .blocked(let why): "Skipped: \(why)"
        case .operation: "Runs a task (later build)"
        }
    }
}

struct RuleDetail: View {
    @Bindable var session: ScanSession
    let result: RuleScanResult
    @Environment(AppModel.self) private var app

    var body: some View {
        let rule = result.rule
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(rule.title).font(.title2).accessibilityAddTraits(.isHeader)
                    RiskBadge(risk: rule.risk)
                    if rule.status == .experimental {
                        Text("New rule: items start unticked").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Ignore This Category") { app.ignore(.init(kind: .ruleID, value: rule.id)) }
                        .buttonStyle(.link)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow { Text("Removes").foregroundStyle(.secondary); Text(rule.removes) }
                    GridRow { Text("Keeps").foregroundStyle(.secondary); Text(rule.keeps) }
                    GridRow {
                        Text("Goes to").foregroundStyle(.secondary)
                        Text(rule.action == .delete ? "Deleted permanently (caches and logs are re-created)" : "The Trash, where you can restore it")
                    }
                    GridRow { Text("Source").foregroundStyle(.secondary); Text(rule.source.origin == "own" ? "TidyMyMac" : rule.source.origin) }
                    if rule.privilege == .helper {
                        GridRow { Text("Needs").foregroundStyle(.secondary); Label("Your administrator password, once per run", systemImage: "lock.fill") }
                    }
                }
                .font(.callout)
                if rule.risk == .risky {
                    Label("These items may be the only copy of something. Tick each one you're sure about.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.red)
                }
            }
            .padding(20)
            Divider()
            if result.candidates.isEmpty {
                EmptyStateView(symbol: "checkmark.circle", message: emptyMessage) {
                    if result.state == .needsFullDiskAccess || result.state == .requiresHelper {
                        Button("Open Setup") { app.showSetup = true }
                    }
                }
            } else {
                ItemTable(session: session, items: result.candidates)
            }
        }
    }

    var emptyMessage: String {
        switch result.state {
        case .needsFullDiskAccess: "This category needs Full Disk Access. Open setup to turn it on."
        case .requiresHelper: "This category needs the admin helper. Open setup to install it."
        case .blocked(let why): "Skipped because \(why)."
        case .operation: "This task runs from Maintenance in a later build."
        case .notForThisMacOS: "This rule doesn't apply to this version of macOS."
        case .scanned: "Nothing left to remove in \(result.rule.title)."
        }
    }
}

struct ScanningView: View {
    let session: ScanSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let done = session.progress.values.filter { $0 }.count
        let total = max(session.progress.count, 1)
        HStack(alignment: .center, spacing: 40) {
            VStack(spacing: 16) {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 10)
                    Circle().trim(from: 0, to: Double(done) / Double(total))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: done)
                    Text("\(done) of \(total)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                .frame(width: 120, height: 120)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Scan progress")
                .accessibilityValue("\(done) of \(total) areas checked")
                Text("Found \(sizeString(session.foundSoFar + session.foundInCurrent)) so far")
                    .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(session.currentArea.map { "Checking \($0)…" } ?? "Finishing…")
                    .foregroundStyle(.secondary)
                Button("Stop") { session.stopScan() }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(session.areas, id: \.id) { area in
                    let finished = session.progress[area.id] == true
                    let current = !finished && session.currentArea.map { area.title.hasPrefix($0) } == true
                    HStack(spacing: 8) {
                        if finished {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if current {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "circle").foregroundStyle(.tertiary)
                        }
                        Text(area.title).foregroundStyle(finished || current ? .primary : .secondary)
                    }
                    .font(.callout)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(area.title)
                    .accessibilityValue(finished ? "Done" : (current ? "Checking" : "Waiting"))
                }
            }
            .frame(minWidth: 220, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Manage the ignore list (build spec §6.3), from the Cleanup toolbar and Settings › Cleanup.
struct IgnoreListView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ignore List").font(.title2)
            Text("Ignored items and categories never show up in scans. Removing an entry brings it back on the next scan.")
                .foregroundStyle(.secondary)
            if app.ignoreList.entries.isEmpty {
                EmptyStateView(symbol: "eye.slash", message: "Nothing is ignored.")
            } else {
                List(app.ignoreList.entries, id: \.self) { e in
                    HStack {
                        Image(systemName: e.kind == .path ? "doc" : "square.stack")
                            .accessibilityLabel(e.kind == .path ? "Item" : "Category")
                        Text(e.kind == .ruleID ? (app.context?.rules.cleanRule(e.value)?.title ?? e.value) : e.value)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(e.added).foregroundStyle(.secondary)
                        Button { app.unignore(e) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain).help("Stop ignoring")
                            .accessibilityLabel("Stop ignoring \(e.kind == .ruleID ? (app.context?.rules.cleanRule(e.value)?.title ?? e.value) : (e.value as NSString).lastPathComponent)")
                    }
                }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20)
    }
}
