import HelperProtocol
import RuleEngine
import RunLog
import SwiftUI

/// Performance (spec 007 §2). Maintenance runs through the admin helper (005 §6.3); Login Items
/// and Background Items per build spec §6.9.
struct PerformanceView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case maintenance = "Maintenance", loginItems = "Login Items", backgroundItems = "Background Items"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Group {
            switch app.performanceTab {
            case .maintenance: MaintenanceView()
            case .loginItems: LoginItemsView()
            case .backgroundItems: BackgroundItemsView()
            }
        }
        .toolbar {
            Picker("View", selection: $app.performanceTab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
        }
    }
}

struct MaintenanceView: View {
    @Environment(AppModel.self) private var app
    @State private var volumes: [VolumeStatus] = []
    @State private var snapshots: [String] = []
    @State private var busy = false
    @State private var confirm: Pending?

    struct Pending: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let button: String
        let request: HelperRequest
        let logID: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !app.helper.state.isReady {
                    GroupBox {
                        HStack {
                            Label("These tasks need the admin helper.", systemImage: "lock.shield").foregroundStyle(.secondary)
                            Spacer()
                            Button("Open Setup") { app.showSetup = true }
                        }
                        .padding(8)
                    }
                }
                task(title: "Flush DNS cache", symbol: "network",
                     detail: "Clears the list of website addresses macOS remembers. Helps when sites won't load after a network change. No password needed.") {
                    Button("Flush") { Task { await perform(.flushDNS, logID: "task.flushDNS", done: "DNS cache flushed") } }
                }
                task(title: "Reindex Spotlight", symbol: "magnifyingglass",
                     detail: "Rebuilds the search index for a disk. Searches are incomplete for a while afterwards, and the Mac works harder until it finishes.") {
                    if volumes.isEmpty { Text("No disks listed yet.").foregroundStyle(.secondary) }
                    ForEach(volumes, id: \.uuid) { v in
                        HStack {
                            Text(v.name)
                            Text(v.indexingEnabled == false ? "Indexing off" : "").foregroundStyle(.secondary)
                            Spacer()
                            Button("Reindex…") {
                                confirm = Pending(title: "Reindex \(v.name)?", message: "Spotlight rebuilds this disk's index. It can take an hour or more.",
                                                  button: "Reindex", request: .reindexSpotlight(volumeUUID: v.uuid, dryRun: false), logID: "task.reindexSpotlight")
                            }
                        }
                    }
                }
                task(title: "Thin Time Machine snapshots", symbol: "clock.arrow.circlepath",
                     detail: "Local Time Machine snapshots hold space until macOS needs it. Deleting them frees that space now; your backups on the backup disk are not touched.") {
                    if snapshots.isEmpty { Text("No local snapshots.").foregroundStyle(.secondary) }
                    ForEach(snapshots, id: \.self) { s in
                        HStack {
                            Text(s).monospacedDigit()
                            Spacer()
                            Button("Delete…") {
                                confirm = Pending(title: "Delete the snapshot from \(s)?", message: "This local snapshot is deleted permanently.",
                                                  button: "Delete", request: .deleteLocalSnapshot(date: s, dryRun: false), logID: "task.deleteLocalSnapshot")
                            }
                        }
                    }
                }
            }
            .padding(20)
            .disabled(!app.helper.state.isReady || busy)
        }
        .task(id: app.helper.state) { await reload() }
        .alert(confirm?.title ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { p in
            Button(p.button, role: .destructive) { Task { await perform(p.request, logID: p.logID, done: "Done") } }
            Button("Cancel", role: .cancel) {}
        } message: { p in Text(p.message) }
    }

    @ViewBuilder
    func task<Actions: View>(title: String, symbol: String, detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(title, systemImage: symbol).font(.headline)
                    Spacer()
                    Image(systemName: "lock.fill").foregroundStyle(.secondary).help("Runs through the admin helper")
                }
                Text(detail).font(.callout).foregroundStyle(.secondary)
                actions()
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func reload() async {
        guard app.helper.state.isReady else { return }
        if case .volumes(let v)? = try? await app.helper.send(.spotlightStatus) { volumes = v }
        if case .snapshots(let s)? = try? await app.helper.send(.listLocalSnapshots) { snapshots = s }
    }

    /// Runs one task and logs it like every other run (build spec §6.1).
    func perform(_ request: HelperRequest, logID: String, done: String) async {
        busy = true
        defer { busy = false }
        var result: RunResult = .done
        var reason: String?
        do { _ = try await app.helper.send(request) } catch { result = .failed; reason = "\(error)" }
        app.helper.endAuthorization()
        let item = RunItem(ruleID: logID, path: "", allocatedBytes: 0, action: .operation(logID.replacingOccurrences(of: "task.", with: "")),
                           result: result, reason: reason)
        if let engine = app.engine { _ = try? engine.run([], module: "performance", dryRun: false, extraItems: [item]) }
        app.reloadRuns()
        app.show(result == .done ? done : (reason ?? "Failed"))
        await reload()
    }
}
