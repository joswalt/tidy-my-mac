import AppKit
import Foundation
import HelperProtocol
import Monitors
import Observation
import RuleEngine
import RunLog
import SafetyFloor

/// App-wide state shared by every module.
@MainActor @Observable
final class AppModel {
    private(set) var context: CleanupContext?
    let loadError: String?
    let helper = HelperController()
    var fullDiskAccess: FullDiskAccess.State = .unknown
    var showSetup = false
    var ignoreList = IgnoreList()
    var runs: [RunRecord] = []
    var selectedModule: SidebarModule = .smartCare
    var toast: String?

    let cleanup: ScanSession
    let smartCare: ScanSession

    init() {
        var ctx: CleanupContext?
        var err: String?
        do { ctx = try CompositionRoot.makeContext() } catch { err = "\(error)" }
        context = ctx
        loadError = err
        cleanup = ScanSession(module: "cleanup")
        smartCare = ScanSession(module: "smartCare")
        cleanup.app = self
        smartCare.app = self
        reloadIgnoreList()
        reloadRuns()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSetup() }
        }
        refreshSetup()
        if !UserDefaults.standard.bool(forKey: "setupDismissed") && context != nil { showSetup = true }
        #if DEBUG
        // Debug-only launch arguments for screenshots: -TidyModule cleanup -TidyScan YES.
        // Scans are read-only; nothing here can remove a file.
        let defaults = UserDefaults.standard
        if let m = defaults.string(forKey: "TidyModule"), let module = SidebarModule(rawValue: m) { selectedModule = module }
        if defaults.bool(forKey: "TidyScan") { (selectedModule == .cleanup ? cleanup : smartCare).scan() }
        #endif
    }

    var engine: CleanupEngine? { context.map(CleanupEngine.init) }

    // MARK: Setup (spec 007 §6, 015)

    var isSetUp: Bool { fullDiskAccess == .granted && helper.state.isReady }

    var setupLine: String {
        let fda = switch fullDiskAccess {
        case .granted: "Full Disk Access on"
        case .missing: "Full Disk Access off"
        case .unknown: "Full Disk Access: can't tell"
        }
        return "\(fda) · \(helper.state.summary)"
    }

    /// Re-runs the FDA probe and the helper check (launch, activation, and every second while setup is open).
    func refreshSetup() {
        guard let context else { return }
        let state = FullDiskAccess.state(home: context.home)
        if state != fullDiskAccess || context.hasFullDiskAccess != (state == .granted) {
            let wasGranted = fullDiskAccess == .granted
            fullDiskAccess = state
            self.context = context.with(fullDiskAccess: state == .granted)
            // A new grant reaches the helper after a restart (015 §3).
            if state == .granted && !wasGranted && helper.state.isReady { Task { _ = try? await helper.send(.shutdown) } }
        }
        Task { await helper.refresh() }
    }

    func resetFullDiskAccess() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "SystemPolicyAllFiles", HelperProtocol.appBundleID]
        try? p.run()
        p.waitUntilExit()
        refreshSetup()
        showSetup = true
    }

    // MARK: Ignore list

    func reloadIgnoreList() {
        guard let context else { return }
        ignoreList = (try? context.ignoreStore.load()) ?? IgnoreList()
    }

    func ignore(_ entry: IgnoreList.Entry) {
        guard let context else { return }
        ignoreList.add(entry)
        try? context.ignoreStore.save(ignoreList)
        cleanup.applyIgnoreList()
        smartCare.applyIgnoreList()
        show("Added to the ignore list")
    }

    func unignore(_ entry: IgnoreList.Entry) {
        guard let context else { return }
        ignoreList.remove(entry)
        try? context.ignoreStore.save(ignoreList)
        show("Removed from the ignore list. Scan again to see it.")
    }

    // MARK: Run history

    func reloadRuns() {
        guard let context else { return }
        runs = RunLogReader.runs(in: context.home.tidyRunLogs, limit: 50)
    }

    var lastSmartCare: RunRecord? { runs.first { $0.header.module == "smartCare" && !$0.header.dryRun } }

    func revealRunLogs() {
        guard let context else { return }
        NSWorkspace.shared.open(context.home.tidyRunLogs)
    }

    func restore(_ items: [RunItem]) {
        guard let context else { return }
        let restorer = Restorer(home: context.home)
        var ok = 0
        var last: String?
        var viaHelper: [UUID] = []
        for item in items {
            if let id = item.helperLedgerID.flatMap(UUID.init(uuidString:)) { viaHelper.append(id); continue }
            let r = restorer.restore(item)
            if r == .restored { ok += 1 } else { last = r.description }
        }
        Task {
            if !viaHelper.isEmpty {
                do {
                    if case .results(let rs) = try await helper.send(.restoreTrashed(ledgerIDs: viaHelper)) {
                        ok += rs.filter { $0.outcome == .done }.count
                        if let why = rs.first(where: { $0.outcome != .done })?.reason { last = why }
                    }
                } catch {
                    last = "\(error)"
                }
                helper.endAuthorization()
            }
            if ok > 0 { show("Restored \(ok) \(ok == 1 ? "item" : "items")") } else if let last { show(last) }
            restoreTick += 1
        }
    }

    /// Bumped after restores so run detail re-checks what can still be restored.
    var restoreTick = 0

    func restoreState(_ item: RunItem) -> Restorer.Result {
        guard let context else { return .notTrashed }
        let r = Restorer(home: context.home).check(item)
        if r == .needsHelper && helper.state.isReady { return .restored }
        return r
    }

    func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toast == message { toast = nil }
        }
    }
}

/// One module's scan → review → run cycle (Cleanup and Smart Care each have one).
@MainActor @Observable
final class ScanSession {
    enum Phase: Equatable {
        case idle, scanning, results, running
        case done(dryRun: Bool)
    }

    let module: String
    weak var app: AppModel?
    var phase: Phase = .idle
    var report: ScanReport?
    var selection = Selection()
    var lastRun: CleanupEngine.Run?
    var foundSoFar: Int64 = 0
    var progress: [String: Bool] = [:]
    var error: String?
    private var scanTask: Task<Void, Never>?

    init(module: String) { self.module = module }

    var candidates: [Candidate] { report?.candidates ?? [] }
    var selected: [Candidate] { selection.selected(from: candidates) }
    var summary: CleanupSummary { CleanupSummary(selected) }

    var rules: [CleanRule] {
        guard let ctx = app?.context else { return [] }
        return module == "smartCare" ? ctx.smartCareRules : ctx.cleanupRules
    }

    func scan() {
        guard let engine = app?.engine, let ignore = app?.ignoreList else { return }
        let rules = self.rules
        let previous = phase == .scanning ? .idle : phase
        phase = .scanning
        foundSoFar = 0
        progress = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, false) })
        scanTask = Task {
            var results: [RuleScanResult] = []
            for rule in rules {
                if Task.isCancelled { phase = previous; return }
                let r = await Task.detached { engine.scan([rule], ignore: ignore).results }.value
                results += r
                foundSoFar += r.reduce(0) { $0 + $1.totalBytes }
                progress[rule.id] = true
            }
            // Helper rules: ask the helper for its zones, then narrow by each rule (005 §5).
            if let app, app.helper.state.isReady {
                let helperRules = rules.filter { $0.privilege == .helper && $0.zone != nil }
                let found = await app.helper.found(in: Set(helperRules.compactMap(\.zone)))
                let home = engine.context.home
                for rule in helperRules {
                    var r = HelperRuleMatcher.result(for: rule, items: found, home: home)
                    r.candidates = r.candidates.filter { !ignore.ignores($0) }
                    results.removeAll { $0.rule.id == rule.id }
                    results.append(r)
                    foundSoFar += r.totalBytes
                }
            }
            // Trash bins (build spec §6.4).
            let ctx = engine.context
            let bins = await Task.detached { TrashBins.results(home: ctx.home, floor: ctx.floor, hasFullDiskAccess: ctx.hasFullDiskAccess) }.value
            results += bins
            foundSoFar += bins.reduce(0) { $0 + $1.totalBytes }
            // Categories with items first, safest first, then largest.
            let order: [RuleRisk: Int] = [.safe: 0, .caution: 1, .risky: 2]
            results.sort { a, b in
                let ka = (a.candidates.isEmpty ? 1 : 0, order[a.rule.risk]!, -a.totalBytes)
                let kb = (b.candidates.isEmpty ? 1 : 0, order[b.rule.risk]!, -b.totalBytes)
                return ka < kb
            }
            let report = ScanReport(results: results)
            self.report = report
            selection = Selection.defaults(for: report.candidates)
            phase = .results
        }
    }

    func stopScan() { scanTask?.cancel() }

    func applyIgnoreList() {
        guard let ignore = app?.ignoreList, let report else { return }
        self.report = ScanReport(results: report.results.map { r in
            var r = r
            r.candidates = r.candidates.filter { !ignore.ignores($0) }
            return r
        })
        selection.keepOnly(candidates)
    }

    /// Every action in one run log: helper items, Trash bins and user-level items (spec 005 §8).
    func run(dryRun: Bool, extraItems: [RunItem] = [], flushDNS: Bool = false) {
        guard let app, let engine = app.engine else { return }
        let items = selected
        let module = self.module
        let helperItems = items.filter(\.viaHelper)
        let trashItems = items.filter(TrashBins.isTrashItem)
        let userItems = items.filter { !$0.viaHelper && !TrashBins.isTrashItem($0) }
        phase = .running
        Task {
            var extra = extraItems
            if flushDNS && !dryRun {
                var r: RunResult = .done
                var why: String?
                do { _ = try await app.helper.send(.flushDNS) } catch { r = .failed; why = "\(error)" }
                extra.append(RunItem(ruleID: "task.flushDNS", path: "", allocatedBytes: 0, action: .operation("flushDNS"), result: r, reason: why))
            }
            // 1. Through the admin helper (one password prompt for the run).
            if !helperItems.isEmpty {
                extra += await runHelper(helperItems, dryRun: dryRun)
            }
            // 2. Trash bins: ledger items through the helper, the user's own items here.
            if !trashItems.isEmpty {
                extra += await emptyTrash(trashItems, dryRun: dryRun)
            }
            app.helper.endAuthorization()
            do {
                let run = try await Task.detached { try engine.run(userItems, module: module, dryRun: dryRun, extraItems: extra) }.value
                lastRun = run
                phase = .done(dryRun: dryRun)
            } catch {
                self.error = "\(error)"
                phase = .results
            }
            app.reloadRuns()
        }
    }

    private func runHelper(_ items: [Candidate], dryRun: Bool) async -> [RunItem] {
        guard let app else { return [] }
        let byHandle = Dictionary(uniqueKeysWithValues: items.compactMap { c in c.helperHandle.map { ($0, c) } })
        do {
            let reply = try await app.helper.send(.remove(handles: items.compactMap { $0.helperHandle.map(HelperHandle.init) },
                                                          dryRun: dryRun, jobID: UUID()))
            guard case .results(let rs) = reply else { return [] }
            return rs.map { r in
                let c = r.handle.flatMap { byHandle[$0.raw] }
                return RunItem(ruleID: c?.ruleID ?? "helper", path: c?.path ?? r.path, allocatedBytes: c?.allocatedBytes ?? r.allocatedBytes,
                               action: r.action == "trash" ? .trash : .delete,
                               result: r.outcome == .done ? .done : (r.outcome == .skipped ? .skipped : .failed),
                               reason: r.reason, trashPath: r.trashPath, helperLedgerID: r.ledgerID?.uuidString)
            }
        } catch {
            return items.map { RunItem(ruleID: $0.ruleID, path: $0.path, allocatedBytes: $0.allocatedBytes,
                                       action: $0.action == .delete ? .delete : .trash, result: .skipped, reason: "\(error)") }
        }
    }

    private func emptyTrash(_ items: [Candidate], dryRun: Bool) async -> [RunItem] {
        guard let app, let ctx = app.context else { return [] }
        let ledger = app.helper.state.isReady ? await app.helper.ledger() : []
        let byTrashPath = Dictionary(uniqueKeysWithValues: ledger.map { ($0.trashPath, $0.id) })
        let ledgerItems = items.filter { byTrashPath[$0.path] != nil }
        let own = items.filter { byTrashPath[$0.path] == nil }
        var out: [RunItem] = []
        if !ledgerItems.isEmpty {
            if dryRun {
                out += ledgerItems.map { RunItem(ruleID: TrashBins.ruleID, path: $0.path, allocatedBytes: $0.allocatedBytes, action: .delete, result: .done) }
            } else if case .results(let rs)? = try? await app.helper.send(.emptyTrashed(ledgerIDs: ledgerItems.compactMap { byTrashPath[$0.path] })) {
                out += rs.map { RunItem(ruleID: TrashBins.ruleID, path: $0.path, allocatedBytes: $0.allocatedBytes, action: .delete,
                                        result: $0.outcome == .done ? .done : .failed, reason: $0.reason) }
            } else {
                out += ledgerItems.map { RunItem(ruleID: TrashBins.ruleID, path: $0.path, allocatedBytes: $0.allocatedBytes, action: .delete,
                                                 result: .skipped, reason: "The admin helper couldn't empty it.") }
            }
        }
        out += await Task.detached { TrashEmptier.empty(own, home: ctx.home, floor: ctx.floor, dryRun: dryRun) }.value
        return out
    }

    /// After a real run, the old results are stale.
    func finish() {
        if case .done(let dry) = phase, !dry {
            report = nil
            selection = Selection()
            phase = .idle
        } else {
            phase = report == nil ? .idle : .results
        }
    }
}
