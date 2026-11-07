import HelperProtocol
import RuleEngine
import RunLog
import SafetyFloor
import SwiftUI
import SystemTasks

/// Performance › Login Items (build spec §6.9): TidyMyMac's own switch, and the way to the
/// system's list. macOS has no public API for other apps' login items, so none is faked.
struct LoginItemsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Open TidyMyMac at login", isOn: Binding(get: { app.loginItem.isOn }, set: { app.loginItem.set($0) }))
                            .toggleStyle(.switch)
                        Text("Keeps the menu bar monitors and alerts running after you log in.").font(.callout).foregroundStyle(.secondary)
                        if let e = app.loginItem.error { Text(e).font(.caption).foregroundStyle(.orange) }
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Other apps' login items", systemImage: "person.crop.circle.badge.checkmark").font(.headline)
                        Text("macOS lists the apps that open at login, and the items they added, in System Settings › General › Login Items & Extensions. Only there can they be switched off, so TidyMyMac doesn't show its own copy of that list. Launch agents and daemons are in the Background Items tab.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Open Login Items Settings") { app.loginItem.openSettings() }
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .onAppear { app.loginItem.refresh() }
    }
}

/// Performance › Background Items (build spec §6.9). Switching is reversible and logged;
/// removing broken items is Cleanup's job.
struct BackgroundItemsView: View {
    @Environment(AppModel.self) private var app
    @State private var items: [BackgroundItem] = []
    @State private var loading = false
    @State private var busy: String?

    var body: some View {
        Group {
            if loading && items.isEmpty {
                ProgressView("Reading launch agents and daemons…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                EmptyStateView(symbol: "gearshape.2", message: "No background items besides Apple's own.")
            } else {
                List {
                    ForEach(BackgroundItem.Domain.allCases, id: \.self) { domain in
                        let rows = items.filter { $0.domain == domain }
                        if !rows.isEmpty {
                            Section {
                                ForEach(rows) { row($0) }
                            } header: {
                                Text(domain.title)
                            } footer: {
                                if domain.needsHelper && !app.helper.state.isReady {
                                    Text("Switching launch daemons needs the admin helper.").font(.caption)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task { await reload() }
        .toolbar {
            Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .help("Read the list again")
        }
    }

    func row(_ item: BackgroundItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.label).lineLimit(1)
                    if !item.programExists {
                        Text("Program missing").font(.caption).padding(.horizontal, 6).foregroundStyle(.orange)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .help("The program this item starts is gone. Cleanup › Broken login items can remove it.")
                    }
                }
                Text([item.vendor, item.program.map { ($0 as NSString).lastPathComponent }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .help(item.program ?? "")
            }
            Spacer()
            Text(item.disabled ? "Off" : (item.loaded ? "Running" : "Not loaded")).font(.caption).foregroundStyle(.secondary)
            if busy == item.id { ProgressView().controlSize(.small) }
            Toggle("Enabled", isOn: Binding(get: { !item.disabled }, set: { on in Task { await set(item, enabled: on) } }))
                .labelsHidden().toggleStyle(.switch)
                .disabled(busy != nil || (item.domain.needsHelper && !app.helper.state.isReady))
                .help(item.domain.needsHelper ? "Switches through the admin helper (asks for your password)" : "Switch this item off or on")
                .accessibilityLabel("\(item.label) enabled")
        }
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.plistPath)]) }
        }
    }

    func reload() async {
        guard let home = app.context?.home else { return }
        loading = true
        let bg = CompositionRoot.makeBackgroundItems(home: home)
        items = await Task.detached { bg.list() }.value
        loading = false
    }

    /// Switches one item and logs it like every other run (build spec §6.1, §6.9).
    func set(_ item: BackgroundItem, enabled: Bool) async {
        guard let home = app.context?.home else { return }
        busy = item.id
        defer { busy = nil }
        var result: RunResult = .done
        var reason: String?
        if item.domain.needsHelper {
            // Daemons: only through a handle the helper issued for this plist (spec 005).
            let found = await app.helper.found(in: [.launchItems])
            if let h = found.first(where: { $0.path == item.plistPath })?.handle {
                do { _ = try await app.helper.send(.setDaemonEnabled(handle: HelperHandle(h), enabled: enabled, dryRun: false)) } catch {
                    result = .failed; reason = "\(error)"
                }
                app.helper.endAuthorization()
            } else {
                result = .skipped; reason = "The admin helper didn't list this daemon."
            }
        } else {
            let bg = CompositionRoot.makeBackgroundItems(home: home)
            if case .failure(let e) = await Task.detached(operation: { bg.setAgent(item, enabled: enabled, dryRun: false) }).value {
                result = .failed; reason = e.description
            }
        }
        let op = enabled ? "enableLaunchItem" : "disableLaunchItem"
        let logItem = RunItem(ruleID: "task.backgroundItem", path: item.plistPath, allocatedBytes: 0, action: .operation(op), result: result, reason: reason)
        if let engine = app.engine { _ = try? engine.run([], module: "performance", dryRun: false, extraItems: [logItem]) }
        app.reloadRuns()
        app.show(result == .done ? "\(item.label) switched \(enabled ? "on" : "off")" : (reason ?? "Failed"))
        await reload()
    }
}
