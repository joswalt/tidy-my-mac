import RuleEngine
import SwiftUI

/// Smart Care: one scan → result cards → review → one confirm → done (spec 007 §3).
/// In this build only the Cleanup card is live; the others arrive with later milestones.
struct SmartCareView: View {
    @Environment(AppModel.self) private var app
    @State private var showReview = false
    @State private var showConfirm = false
    @State private var flushDNS = true

    var session: ScanSession { app.smartCare }

    var body: some View {
        @Bindable var session = session
        VStack(spacing: 0) {
            switch session.phase {
            case .idle: idle
            case .scanning: ScanningView(session: session)
            case .running: ProgressView("Cleaning…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done(let dry):
                if let run = session.lastRun { RunResultView(run: run, dryRun: dry) { session.finish() } }
            case .results: results(session)
            }
        }
        .toolbar {
            Button { session.scan() } label: { Label("Scan", systemImage: "arrow.clockwise") }
                .help("Scan (⌘R)")
                .keyboardShortcut("r")
                .disabled(session.phase == .scanning || session.phase == .running)
        }
        .sheet(isPresented: $showReview) { ReviewSheet(session: session) { showConfirm = true } }
        .cleanConfirm($showConfirm, summary: session.summary, adminItems: session.selected.filter(\.viaHelper)) { session.run(dryRun: false, flushDNS: flushDNS && app.helper.state.isReady) }
    }

    var idle: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Checks caches, logs and leftover junk in one scan. Nothing is removed until you review it.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            Button("Scan") { session.scan() }
                .buttonStyle(.borderedProminent).controlSize(.extraLarge)
            HStack(spacing: 8) {
                ForEach(["Cleanup", "Trash", "Applications", "Maintenance", "My Clutter", "Protection"], id: \.self) {
                    Text($0).font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            if let last = app.lastSmartCare {
                Text("Last run \(last.header.start.formatted(.relative(presentation: .named)))").font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    func results(_ session: ScanSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sizeString(session.summary.totalBytes))
                        .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(session.summary.itemCount == 0
                         ? "Nothing is ticked yet. New rules start unticked: open Review to choose."
                         : "selected to clean")
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    CleanupCard(session: session) { showReview = true }
                    TrashCard(session: session)
                    LaterCard(title: "Applications", symbol: "square.grid.2x2", note: "Leftovers and updates arrive in a later build.")
                    MaintenanceCard(flushDNS: $flushDNS)
                    LaterCard(title: "My Clutter", symbol: "doc.on.doc", note: "Large and old files arrive in a later build. Smart Care never cleans personal files.")
                    LaterCard(title: "Protection", symbol: "lock.shield", note: "Review app permissions (later build).")
                }
            }
            .padding(20)
        }
        FooterBar(summary: session.summary.line) {
            Button("Review All…") { showReview = true }.disabled(session.candidates.isEmpty)
            Button(session.summary.itemCount == 0 ? "Clean" : "Clean \(sizeString(session.summary.totalBytes))") { showConfirm = true }
                .buttonStyle(.borderedProminent)
                .disabled(session.summary.itemCount == 0)
        }
    }
}

struct CleanupCard: View {
    @Bindable var session: ScanSession
    let onReview: () -> Void

    var body: some View {
        let all = session.candidates.filter { !TrashBins.isTrashItem($0) }
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if !all.isEmpty {
                        TriStateBox(state: session.selection.state(of: all)) {
                            session.selection.setGroup(all, session.selection.state(of: all) != .all)
                        }
                    }
                    Label("Cleanup", systemImage: "bubbles.and.sparkles").font(.headline)
                    Spacer()
                    Text(sizeString(session.report?.totalBytes ?? 0)).monospacedDigit().foregroundStyle(.secondary)
                }
                Text("Caches, logs, Xcode junk and broken login items.").font(.callout).foregroundStyle(.secondary)
                Text("\(all.count) items found · \(session.selected.count) selected").font(.callout.monospacedDigit())
                Button("Review…", action: onReview).disabled(all.isEmpty)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

struct LaterCard: View {
    let title: String
    let symbol: String
    let note: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol).font(.headline)
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .padding(8)
        }
        .opacity(0.6)
    }
}

/// Trash card: starts unticked, emptying is permanent (spec 007 §3, build spec §6.4).
struct TrashCard: View {
    @Bindable var session: ScanSession
    @Environment(AppModel.self) private var app

    var body: some View {
        let items = session.candidates.filter(TrashBins.isTrashItem)
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if !items.isEmpty {
                        TriStateBox(state: session.selection.state(of: items)) {
                            session.selection.setGroup(items, session.selection.state(of: items) != .all)
                        }
                    }
                    Label("Trash", systemImage: "trash").font(.headline)
                    Spacer()
                    Text(sizeString(items.reduce(0) { $0 + $1.allocatedBytes })).monospacedDigit().foregroundStyle(.secondary)
                }
                if app.fullDiskAccess != .granted {
                    Text("Needs Full Disk Access to see what's in the Trash.").font(.callout).foregroundStyle(.secondary)
                    Button("Open Setup") { app.showSetup = true }
                } else {
                    Label("Emptying the Trash is permanent.", systemImage: "flame").font(.callout).foregroundStyle(.red)
                    Text("\(items.count) items").font(.callout.monospacedDigit())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

/// Maintenance card: Flush DNS on by default; the other tasks live in Performance (spec 007 §3).
struct MaintenanceCard: View {
    @Binding var flushDNS: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Maintenance", systemImage: "gauge.with.dots.needle.67percent").font(.headline)
                if app.helper.state.isReady {
                    Toggle("Flush DNS cache", isOn: $flushDNS)
                    Button("Spotlight and Time Machine…") { app.selectedModule = .performance }.buttonStyle(.link)
                } else {
                    Text("Needs the admin helper.").font(.callout).foregroundStyle(.secondary)
                    Button("Open Setup") { app.showSetup = true }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .padding(8)
        }
    }
}
