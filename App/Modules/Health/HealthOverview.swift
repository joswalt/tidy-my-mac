import Monitors
import RuleEngine
import SwiftUI

extension HealthLevel {
    var color: Color {
        switch self { case .good: .green; case .worthALook: .orange; case .needsAttention: .red }
    }
}

/// Health › Overview (spec 012 §1–3). Refreshed on launch, when it opens and after every run;
/// nothing scans in the background.
struct HealthOverview: View {
    @Environment(AppModel.self) private var app
    @State private var showTrashConfirm = false

    var body: some View {
        let status = app.status
        let signals = status.signals
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(status.overall, checked: status.checkedAt)
                GroupBox {
                    VStack(spacing: 0) {
                        ForEach(Array(signals.enumerated()), id: \.element.id) { i, s in
                            if i > 0 { Divider() }
                            SignalRow(signal: s) { fix(s.fix) }
                        }
                        if app.applications.updateCount > 0 {
                            Divider()
                            HStack {
                                Image(systemName: "arrow.down.app").foregroundStyle(.secondary).frame(width: 12)
                                Text("App updates")
                                Spacer()
                                let n = app.applications.updateCount
                                Button(n == 1 ? "1 update" : "\(n) updates") {
                                    app.applications.tab = .updates
                                    app.selectedModule = .applications
                                }
                                .buttonStyle(.link)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                HStack(alignment: .top, spacing: 16) {
                    StorageCard(storage: status.storage)
                    TrashHealthCard(onEmpty: emptyTrash)
                }
                HStack(alignment: .top, spacing: 16) {
                    RemindersCard()
                    SetupCard()
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .onAppear { app.status.refresh() }
        .cleanConfirm($showTrashConfirm, summary: app.trashSession.summary) { app.trashSession.run(dryRun: false) }
        .onChange(of: app.trashSession.phase) { _, phase in
            if case .done = phase, let run = app.trashSession.lastRun {
                let bytes = run.outcome.done.reduce(Int64(0)) { $0 + $1.allocatedBytes }
                app.show(bytes > 0 ? "Emptied \(sizeString(bytes)) from the Trash" : "Nothing was emptied; see Run History")
                app.trashSession.finish()
            }
        }
    }

    func header(_ level: HealthLevel, checked: Date?) -> some View {
        HStack(spacing: 14) {
            Circle().fill(level.color.gradient).frame(width: 28, height: 28)
                .overlay(Image(systemName: level == .good ? "checkmark" : "exclamationmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(level.title).font(.title.weight(.semibold))
                if let checked {
                    Text("Checked \(checked.formatted(date: .omitted, time: .shortened))").font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { app.status.refresh(); app.refreshSetup() } label: { Label("Check Again", systemImage: "arrow.clockwise") }
        }
    }

    func fix(_ fix: HealthSignal.Fix?) {
        switch fix {
        case .spaceLens: app.selectedModule = .spaceLens
        case .runSmartCare: app.runSmartCare()
        case .smartCare:
            app.selectedModule = .smartCare
            if app.smartCare.report == nil && app.smartCare.phase == .idle { app.smartCare.scan() }
        case .emptyTrash: emptyTrash()
        case .openSetup: app.showSetup = true
        case nil: break
        }
    }

    func emptyTrash() {
        Task {
            await app.trashSession.loadTrashOnly()
            if app.trashSession.summary.itemCount > 0 { showTrashConfirm = true } else { app.show("The Trash is empty") }
        }
    }
}

struct SignalRow: View {
    let signal: HealthSignal
    let onFix: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(signal.level.color).frame(width: 10, height: 10).accessibilityLabel(signal.level.title)
            VStack(alignment: .leading, spacing: 1) {
                Text(signal.title)
                Text(signal.reason).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if let fix = signal.fix {
                Button(Self.title(fix), action: onFix)
            }
        }
        .padding(.vertical, 8)
    }

    static func title(_ fix: HealthSignal.Fix) -> String {
        switch fix {
        case .spaceLens: "Space Lens"
        case .runSmartCare: "Run Smart Care"
        case .smartCare: "Smart Care"
        case .emptyTrash: "Empty Trash…"
        case .openSetup: "Open Setup"
        }
    }
}

struct StorageCard: View {
    let storage: StorageSample?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Startup disk", systemImage: "internaldrive").font(.headline)
                if let s = storage {
                    ProgressView(value: s.usedFraction).tint(s.usedFraction > 0.9 ? .orange : .accentColor)
                    Text("\(sizeString(s.availableBytes)) available of \(sizeString(s.totalBytes))").monospacedDigit()
                    if s.purgeableBytes > 0 {
                        Text("Includes \(sizeString(s.purgeableBytes)) of purgeable space that macOS frees on its own when it needs room.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Couldn't read the startup disk.").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

struct TrashHealthCard: View {
    @Environment(AppModel.self) private var app
    let onEmpty: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Trash", systemImage: "trash").font(.headline)
                if app.fullDiskAccess != .granted {
                    Text("Needs Full Disk Access").foregroundStyle(.secondary)
                    Button("Open Setup") { app.showSetup = true }
                } else if let t = app.status.trashBytes {
                    Text(t == 0 ? "Empty" : sizeString(t)).monospacedDigit()
                    Text("Alert above \(app.status.trashGB) GB").font(.caption).foregroundStyle(.secondary)
                    Button("Empty Trash…", action: onEmpty).disabled(t == 0)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

struct RemindersCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var status = app.status
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Reminders", systemImage: "bell").font(.headline)
                ReminderControls(status: status)
                if let last = app.lastSmartCare {
                    Text("Last Smart Care \(last.header.start.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

/// On/off, how often and time of day; used by Health and Settings (spec 012 §3).
struct ReminderControls: View {
    @Bindable var status: StatusModel

    var body: some View {
        Toggle("Remind me to run Smart Care", isOn: $status.remindersOn)
        Picker("How often", selection: $status.reminderInterval) {
            ForEach(ReminderInterval.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .disabled(!status.remindersOn)
        DatePicker("Time", selection: Binding(
            get: { Calendar.current.date(bySettingHour: status.reminderMinutes / 60, minute: status.reminderMinutes % 60, second: 0, of: Date()) ?? Date() },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); status.reminderMinutes = (c.hour ?? 10) * 60 + (c.minute ?? 0) }
        ), displayedComponents: .hourAndMinute)
        .disabled(!status.remindersOn)
        if status.notificationsDenied {
            HStack {
                Label("Notifications are off in System Settings", systemImage: "bell.slash").font(.caption).foregroundStyle(.orange)
                Button("Open") { status.openNotificationSettings() }.buttonStyle(.link).font(.caption)
            }
        }
        Text("A notification only. TidyMyMac never scans or cleans on its own.").font(.caption).foregroundStyle(.secondary)
    }
}

struct SetupCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Setup", systemImage: "lock.shield").font(.headline)
                HStack { Circle().fill(app.fullDiskAccess == .granted ? .green : .orange).frame(width: 8, height: 8)
                    Text(app.fullDiskAccess == .granted ? "Full Disk Access on" : (app.fullDiskAccess == .missing ? "Full Disk Access off" : "Full Disk Access: can't tell")) }
                HStack { Circle().fill(app.helper.state.isReady ? .green : .orange).frame(width: 8, height: 8)
                    Text(app.helper.state.summary) }
                Button("Open Setup") { app.showSetup = true }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}
