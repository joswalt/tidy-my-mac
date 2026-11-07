import Foundation
import RunLog
import SafetyFloor

/// Everything a cleanup needs from the outside world, built once by the app's composition root
/// (or by tests from a `TestHome`).
public struct CleanupContext: Sendable {
    public let home: Home
    public let rules: RuleSet
    public let floor: ProtectedFloor
    public let guards: GuardEnvironment
    public let hasFullDiskAccess: Bool
    public let trash: TrashMover
    public let unloader: LaunchItemUnloader?
    public let appVersion: String

    public init(home: Home, rules: RuleSet, guards: GuardEnvironment, hasFullDiskAccess: Bool, trash: TrashMover,
                unloader: LaunchItemUnloader?, appVersion: String) {
        self.home = home
        self.rules = rules
        self.floor = ProtectedFloor(home: home, additions: rules.floorAdditions(home: home))
        self.guards = guards
        self.hasFullDiskAccess = hasFullDiskAccess
        self.trash = trash
        self.unloader = unloader
        self.appVersion = appVersion
    }

    public var scanner: RuleScanner {
        RuleScanner(home: home, floor: floor, guards: guards, hasFullDiskAccess: hasFullDiskAccess)
    }

    public var ignoreStore: IgnoreStore { IgnoreStore(home: home) }

    /// Rules shown in the Cleanup module (user-level ones scan now; helper ones say so).
    public var cleanupRules: [CleanRule] { rules.cleanRules.filter { $0.module == .cleanup } }

    /// Smart Care never includes risky rules (spec 006 §4).
    public var smartCareRules: [CleanRule] { cleanupRules.filter { $0.risk != .risky } }
}

/// The live summary shown in every footer and confirm (spec 007 §1, §3).
public struct CleanupSummary: Equatable, Sendable {
    public var itemCount = 0
    public var trashBytes: Int64 = 0
    public var deleteBytes: Int64 = 0

    public var totalBytes: Int64 { trashBytes + deleteBytes }

    public init(_ items: some Sequence<Candidate>) {
        for c in items {
            itemCount += 1
            if c.action == .delete { deleteBytes += c.allocatedBytes } else { trashBytes += c.allocatedBytes }
        }
    }

    public static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    /// "1,284 items · 1.3 GB to Trash · 7.7 GB deleted permanently"
    public var line: String {
        guard itemCount > 0 else { return "Nothing selected" }
        var parts = ["\(itemCount.formatted()) \(itemCount == 1 ? "item" : "items")"]
        if trashBytes > 0 || deleteBytes == 0 { parts.append("\(Self.size(trashBytes)) to Trash") }
        if deleteBytes > 0 { parts.append("\(Self.size(deleteBytes)) deleted permanently") }
        return parts.joined(separator: " · ")
    }
}

/// Which items are ticked. Risky items are only ever ticked one by one (spec 006 §4).
public struct Selection: Equatable, Sendable {
    public private(set) var ids: Set<String> = []

    public init(ids: Set<String> = []) { self.ids = ids }

    /// Safe, verified items; never risky ones (and never anything in Smart Care that is risky).
    public static func defaults(for candidates: [Candidate]) -> Selection {
        Selection(ids: Set(candidates.filter { $0.selectedByDefault && $0.risk != .risky }.map(\.id)))
    }

    public func contains(_ c: Candidate) -> Bool { ids.contains(c.id) }

    public mutating func set(_ c: Candidate, _ on: Bool) {
        if on { ids.insert(c.id) } else { ids.remove(c.id) }
    }

    public mutating func toggle(_ c: Candidate) { set(c, !contains(c)) }

    /// Tick or untick a group. Ticking skips risky items: those are ticked one by one.
    public mutating func setGroup(_ items: [Candidate], _ on: Bool) {
        for c in items where !on || c.risk != .risky { set(c, on) }
    }

    public enum GroupState: Sendable { case none, some, all }

    public func state(of items: [Candidate]) -> GroupState {
        let n = items.filter(contains).count
        return n == 0 ? .none : (n == items.count ? .all : .some)
    }

    public func selected(from candidates: [Candidate]) -> [Candidate] { candidates.filter(contains) }

    /// Drops ids that are no longer in the candidates (after a rescan or ignore).
    public mutating func keepOnly(_ candidates: [Candidate]) { ids.formIntersection(candidates.map(\.id)) }
}

/// UI-free cleanup flow: scan, filter by the ignore list, and run a selection with a run log.
public struct CleanupEngine: Sendable {
    public let context: CleanupContext

    public init(context: CleanupContext) { self.context = context }

    /// Scans and hides ignored items (they never reach the review screen).
    public func scan(_ rules: [CleanRule], ignore: IgnoreList) -> ScanReport {
        let ignoredRules = Set(ignore.entries.filter { $0.kind == .ruleID }.map(\.value))
        let report = context.scanner.scan(rules.filter { !ignoredRules.contains($0.id) })
        return ScanReport(results: report.results.map { r in
            var r = r
            r.candidates = r.candidates.filter { !ignore.ignores($0) }
            return r
        })
    }

    public struct Run: Sendable {
        public let outcome: Remover.Outcome
        public let record: RunRecord
        public let logURL: URL
    }

    /// Runs the selection (or, with `dryRun`, only reports it). Every run is logged (§6.1).
    public func run(_ selection: [Candidate], module: String, dryRun: Bool) throws -> Run {
        let header = RunHeader(module: module, appVersion: context.appVersion, ruleSetVersion: context.rules.version, dryRun: dryRun)
        let log = try RunLogWriter(directory: context.home.tidyRunLogs, header: header)
        let remover = Remover(scanner: context.scanner, trash: context.trash, unloader: context.unloader)
        let outcome = try remover.run(selection, rules: context.rules, log: log, dryRun: dryRun)
        try log.finish()
        return Run(outcome: outcome, record: try RunLogReader.read(log.fileURL), logURL: log.fileURL)
    }
}
