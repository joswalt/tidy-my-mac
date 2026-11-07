import Foundation
import RunLog
import SafetyFloor

/// An item John picked by hand in My Clutter or Space Lens.
public struct ManualPick: Sendable, Hashable, Identifiable {
    public let path: String
    /// The folder it was found under: the item must still sit inside it, reached without links.
    public let root: String
    /// What it was at scan time; a replaced item is skipped.
    public let identity: ItemIdentity
    public let allocatedBytes: Int64
    /// For a duplicate: every copy of its set. The last copy is never removed (spec 014 §6).
    public let duplicateSet: [String]?

    public init(path: String, root: String, identity: ItemIdentity, allocatedBytes: Int64, duplicateSet: [String]? = nil) {
        self.path = path
        self.root = root
        self.identity = identity
        self.allocatedBytes = allocatedBytes
        self.duplicateSet = duplicateSet
    }

    public var id: String { path }
}

/// Moves hand-picked items to the Trash (build spec §6.6–6.8, spec 014 §5): never deletes,
/// logs every item as rule `manual`, and re-checks each item before it moves (spec 006 §5.4).
public struct ManualRemover: Sendable {
    public static let ruleID = "manual"
    public let context: CleanupContext

    public init(context: CleanupContext) { self.context = context }

    public func run(_ picks: [ManualPick], module: String, dryRun: Bool) throws -> CleanupEngine.Run {
        let header = RunHeader(module: module, appVersion: context.appVersion, ruleSetVersion: context.rules.version, dryRun: dryRun)
        let log = try RunLogWriter(directory: context.home.tidyRunLogs, header: header)
        var outcome = Remover.Outcome()
        var removed: Set<String> = []
        for p in picks {
            let item = process(p, removed: removed, dryRun: dryRun)
            if item.result == .done { removed.insert(p.path) }
            try log.append(item)
            outcome.add(item)
        }
        try log.finish()
        return CleanupEngine.Run(outcome: outcome, record: try RunLogReader.read(log.fileURL), logURL: log.fileURL)
    }

    func skip(_ p: ManualPick, _ reason: String, _ result: RunResult = .skipped) -> RunItem {
        RunItem(ruleID: Self.ruleID, path: p.path, allocatedBytes: p.allocatedBytes, action: .trash, result: result, reason: reason)
    }

    func process(_ p: ManualPick, removed: Set<String>, dryRun: Bool) -> RunItem {
        let status: FileStatus
        do { status = try Containment.validate(item: p.path, root: p.root) } catch { return skip(p, error.description) }
        if status.identity != p.identity { return skip(p, "the item was replaced since the scan") }
        if case .protected(let why) = context.floor.verdict(for: p.path, context: .manualPick) { return skip(p, "protected: \(why)") }
        if let set = p.duplicateSet {
            // Another copy must stay: one not removed in this run (dry or real), still there, same size.
            let survivor = set.contains { o in
                guard o != p.path, !removed.contains(o), let st = FileStatus.lstat(o), st.isRegularFile else { return false }
                return st.size == status.size
            }
            if !survivor { return skip(p, "it is the last copy of this file") }
        }
        let m = Sizer().measure(p.path)
        if m.crossesVolume { return skip(p, "it contains another volume") }
        if m.containsLockedItem { return skip(p, "it contains a locked item") }
        if dryRun { return RunItem(ruleID: Self.ruleID, path: p.path, allocatedBytes: p.allocatedBytes, action: .trash, result: .done) }
        do {
            let dest = try context.trash.moveToTrash(p.path)
            return RunItem(ruleID: Self.ruleID, path: p.path, allocatedBytes: p.allocatedBytes, action: .trash, result: .done, trashPath: dest)
        } catch {
            return skip(p, "\(error)", .failed)
        }
    }
}
