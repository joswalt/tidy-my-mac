import RuleEngine
import SwiftUI

/// Smart Care: one scan → result cards → review → one confirm → done (spec 007 §3).
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
                if let run = session.lastRun {
                    VStack(spacing: 0) {
                        RunResultView(run: run, dryRun: dry) { session.finish() }
                        if !dry { ReminderPrompt() }
                    }
                }
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
                    ApplicationsCard()
                    MaintenanceCard(flushDNS: $flushDNS)
                    ClutterCard()
                    ProtectionCard()
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

/// Applications card (spec 007 §3): leftovers of removed apps and the update count. Look-and-go:
/// leftovers are `caution` items reviewed in Applications, never cleaned by Smart Care itself.
struct ApplicationsCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.applications
        let groups = model.leftovers ?? []
        let bytes = groups.reduce(Int64(0)) { $0 + $1.totalBytes }
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Applications", systemImage: "square.grid.2x2").font(.headline)
                    Spacer()
                    if !groups.isEmpty { Text(sizeString(bytes)).monospacedDigit().foregroundStyle(.secondary) }
                }
                if model.scanningLeftovers {
                    Text("Looking for leftovers…").font(.callout).foregroundStyle(.secondary)
                } else {
                    Text(groups.isEmpty ? "No leftovers of removed apps." : "Leftovers of \(groups.count) removed apps, to review one by one.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Review Leftovers") { open(.leftovers) }.disabled(groups.isEmpty)
                    Button(model.checkingUpdates ? "Checking updates…" : (model.updateCount == 1 ? "1 update" : "\(model.updateCount) updates")) {
                        open(.updates)
                    }
                    .buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .padding(8)
        }
        .onAppear {
            if model.leftovers == nil { model.scanLeftovers() }
            model.checkUpdatesIfDue()
        }
    }

    func open(_ tab: ApplicationsModel.Tab) {
        app.applications.tab = tab
        app.selectedModule = .applications
    }
}

/// Look only (spec 007 §3): the large and old files count, opening My Clutter. Smart Care
/// never cleans personal files.
struct ClutterCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let clutter = app.clutter
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("My Clutter", systemImage: "doc.on.doc").font(.headline)
                    Spacer()
                    if clutter.largeFiles != nil {
                        Text(sizeString(clutter.visibleLarge.reduce(0) { $0 + $1.allocatedBytes })).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Text("Your own files. Smart Care never cleans them; you choose in My Clutter.").font(.callout).foregroundStyle(.secondary)
                if clutter.largeFiles == nil {
                    Text(clutter.scanningLarge ? "Looking for large and old files…" : "Large and old files not checked yet").font(.callout)
                } else {
                    let n = clutter.visibleLarge.count
                    Text("\(n) large or old \(n == 1 ? "file" : "files")").font(.callout.monospacedDigit())
                }
                Button("Open My Clutter…") { clutter.tab = .largeOld; app.selectedModule = .myClutter }
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .padding(8)
        }
        .onAppear { if clutter.largeFiles == nil { clutter.scanLarge() } }
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

/// Protection card: permissions are reviewed in System Settings, so no counts (build spec §6.10).
struct ProtectionCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Protection", systemImage: "lock.shield").font(.headline)
                Text("Review app permissions: camera, microphone, screen recording and more.").font(.callout).foregroundStyle(.secondary)
                Button("Review App Permissions") { app.selectedModule = .protection }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

/// Asked once, on the Done screen of the first Smart Care (spec 012 §2).
struct ReminderPrompt: View {
    @Environment(AppModel.self) private var app
    @AppStorage("reminderPromptAnswered") private var answered = false

    var body: some View {
        if !answered {
            GroupBox {
                HStack {
                    Image(systemName: "bell.badge").font(.title2).foregroundStyle(.tint)
                    Text("Remind me to run Smart Care \(app.status.reminderInterval.title.lowercased())?")
                    Spacer()
                    Button("No Thanks") { app.status.remindersOn = false; answered = true }
                    Button("Remind Me") {
                        app.status.remindersOn = true
                        app.status.requestNotificationPermission()
                        answered = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(8)
            }
            .frame(maxWidth: 560)
            .padding(.bottom, 30)
        }
    }
}
