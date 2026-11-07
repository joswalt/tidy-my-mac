import AppKit
import Foundation
import Observation
import RuleEngine
import RunLog
import SafetyFloor

/// App-wide state shared by every module.
@MainActor @Observable
final class AppModel {
    let context: CleanupContext?
    let loadError: String?
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
        #if DEBUG
        // Debug-only launch arguments for screenshots: -TidyModule cleanup -TidyScan YES.
        // Scans are read-only; nothing here can remove a file.
        let defaults = UserDefaults.standard
        if let m = defaults.string(forKey: "TidyModule"), let module = SidebarModule(rawValue: m) { selectedModule = module }
        if defaults.bool(forKey: "TidyScan") { (selectedModule == .cleanup ? cleanup : smartCare).scan() }
        #endif
    }

    var engine: CleanupEngine? { context.map(CleanupEngine.init) }

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
        var last: Restorer.Result?
        for item in items {
            let r = restorer.restore(item)
            if r == .restored { ok += 1 } else { last = r }
        }
        if ok > 0 { show("Restored \(ok) \(ok == 1 ? "item" : "items")") } else if let last { show(last.description) }
    }

    func restoreState(_ item: RunItem) -> Restorer.Result {
        guard let context else { return .notTrashed }
        return Restorer(home: context.home).check(item)
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

    func run(dryRun: Bool) {
        guard let engine = app?.engine else { return }
        let items = selected
        let module = self.module
        phase = .running
        Task {
            do {
                let run = try await Task.detached { try engine.run(items, module: module, dryRun: dryRun) }.value
                lastRun = run
                phase = .done(dryRun: dryRun)
            } catch {
                self.error = "\(error)"
                phase = .results
            }
            app?.reloadRuns()
        }
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
