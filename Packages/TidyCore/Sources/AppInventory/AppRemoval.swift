import Foundation
import RuleEngine
import RunLog
import SafetyFloor

/// The items of one app (or one missing app's leftovers) removed together.
public struct RemovalBatch: Sendable {
    /// The app the items belong to: it must not be running.
    public let ownerBundleID: String
    /// User-level items, removed here. Items with helper handles are skipped here (the app
    /// removes those through the helper and passes the results as `extraItems`).
    public let items: [Candidate]
    /// Set when the batch must not run, e.g. the helper couldn't move the root-owned app.
    public let blockedReason: String?

    public init(ownerBundleID: String, items: [Candidate], blockedReason: String? = nil) {
        self.ownerBundleID = ownerBundleID
        self.items = items
        self.blockedReason = blockedReason
    }
}

/// Removes reviewed Uninstaller and Leftovers selections: everything to the Trash, every item
/// logged (spec 006 §4, build spec §6.1). Before each item it re-checks what the scan checked
/// (spec 006 §5.4): same item, not a symlink, inside its root, not on the floor, owner app not
/// running, and for an app bundle that it is still the same, non-Apple app.
public struct AppRemovalEngine: Sendable {
    public let context: CleanupContext
    public let signatures: AppSignatures

    public init(context: CleanupContext, signatures: AppSignatures) {
        self.context = context
        self.signatures = signatures
    }

    public func run(_ batches: [RemovalBatch], module: String = "applications", dryRun: Bool,
                    extraItems: [RunItem] = []) throws -> CleanupEngine.Run {
        let log = try startLog(module: module, dryRun: dryRun)
        var outcome = Remover.Outcome()
        try process(batches, extraItems: extraItems, dryRun: dryRun, log: log, outcome: &outcome)
        return try finish(log, outcome)
    }

    /// The same run, then `rootItems` is called with the owners whose app (if any) was removed,
    /// so the app can remove their root-level files through the helper; those results go into
    /// the same run log. An app that stayed keeps its root-level files too.
    public func run(_ batches: [RemovalBatch], module: String = "applications", dryRun: Bool, extraItems: [RunItem] = [],
                    rootItems: @Sendable (_ removedOwners: Set<String>) async -> [RunItem]) async throws -> CleanupEngine.Run {
        let log = try startLog(module: module, dryRun: dryRun)
        var outcome = Remover.Outcome()
        let owners = try process(batches, extraItems: extraItems, dryRun: dryRun, log: log, outcome: &outcome)
        for item in await rootItems(owners) {
            try log.append(item)
            outcome.add(item)
        }
        return try finish(log, outcome)
    }

    func startLog(module: String, dryRun: Bool) throws -> RunLogWriter {
        let header = RunHeader(module: module, appVersion: context.appVersion, ruleSetVersion: context.rules.version, dryRun: dryRun)
        return try RunLogWriter(directory: context.home.tidyRunLogs, header: header)
    }

    func finish(_ log: RunLogWriter, _ outcome: Remover.Outcome) throws -> CleanupEngine.Run {
        try log.finish()
        return CleanupEngine.Run(outcome: outcome, record: try RunLogReader.read(log.fileURL), logURL: log.fileURL)
    }

    /// Returns the owners whose batch wasn't blocked (their app, if any, is gone or would be).
    @discardableResult
    func process(_ batches: [RemovalBatch], extraItems: [RunItem], dryRun: Bool, log: RunLogWriter,
                 outcome: inout Remover.Outcome) throws -> Set<String> {
        func record(_ item: RunItem) throws { try log.append(item); outcome.add(item) }
        var removedOwners: Set<String> = []
        for item in extraItems { try record(item) }
        for batch in batches {
            let running: Set<String>
            do { running = try context.guards.runningBundleIDs().reduce(into: []) { $0.insert(PathNormalizer.fold($1)) } } catch {
                for c in batch.items where !c.viaHelper { try record(skip(c, "\(error)")) }  // can't check: skip (006 §3.1)
                continue
            }
            var blocked = batch.blockedReason
            if blocked == nil, running.contains(PathNormalizer.fold(batch.ownerBundleID)) { blocked = "\(batch.ownerBundleID) is running" }
            // The app bundle goes first; if it can't be removed, its files stay too.
            let ordered = batch.items.filter { $0.ruleID == RelatedFileFinder.appRuleID } + batch.items.filter { $0.ruleID != RelatedFileFinder.appRuleID }
            for c in ordered where !c.viaHelper {
                if let blocked { try record(skip(c, blocked)); continue }
                let item = process(c, ownerBundleID: batch.ownerBundleID, dryRun: dryRun)
                try record(item)
                if c.ruleID == RelatedFileFinder.appRuleID, item.result != .done {
                    blocked = "the app itself wasn't removed (\(item.reason ?? "unknown"))"
                }
            }
            if blocked == nil { removedOwners.insert(batch.ownerBundleID) }
        }
        return removedOwners
    }

    func skip(_ c: Candidate, _ reason: String) -> RunItem {
        RunItem(ruleID: c.ruleID, path: c.path, allocatedBytes: c.allocatedBytes, action: .trash, result: .skipped, reason: reason)
    }

    func process(_ c: Candidate, ownerBundleID: String, dryRun: Bool) -> RunItem {
        guard c.action == .trash else { return skip(c, "Applications only moves items to the Trash") }
        let status: FileStatus
        do { status = try Containment.validate(item: c.path, root: c.root) } catch { return skip(c, error.description) }
        if status.identity != c.identity { return skip(c, "the item was replaced since the scan") }
        if case .protected(let why) = context.floor.verdict(for: c.path, context: .rule) { return skip(c, "protected: \(why)") }
        if DenyList.isAppleItem(c.name) { return skip(c, "Apple's own item") }
        if c.ruleID == RelatedFileFinder.appRuleID {
            guard c.path.hasSuffix(".app"), let info = AppBundleReader.info(c.path) else { return skip(c, "it is no longer an app") }
            if info.bundleID != ownerBundleID { return skip(c, "it is now a different app (\(info.bundleID))") }
            if DenyList.isAppleItem(info.bundleID) || signatures.isAppleSigned(c.path) { return skip(c, "signed by Apple") }
            if status.userID != context.home.userID { return skip(c, "owned by another user; it needs the admin helper") }
        }
        let m = Sizer().measure(c.path)
        if m.crossesVolume { return skip(c, "it contains another volume") }
        if m.containsLockedItem { return skip(c, "it contains a locked item") }
        if m.containsMediaLibrary { return skip(c, "it contains a media library") }
        if dryRun { return RunItem(ruleID: c.ruleID, path: c.path, allocatedBytes: c.allocatedBytes, action: .trash, result: .done) }
        do {
            // A launch agent is unloaded before its plist goes (spec 006 §6, launch.user.broken).
            if !status.isDirectory, c.path.hasSuffix(".plist"), let unloader = context.unloader,
               (c.path as NSString).deletingLastPathComponent == PathNormalizer.realPath(context.home.launchAgents.path) {
                try unloader.unload(plist: c.path, userID: context.home.userID)
            }
            let dest = try context.trash.moveToTrash(c.path)
            return RunItem(ruleID: c.ruleID, path: c.path, allocatedBytes: c.allocatedBytes, action: .trash, result: .done, trashPath: dest)
        } catch {
            return RunItem(ruleID: c.ruleID, path: c.path, allocatedBytes: c.allocatedBytes, action: .trash, result: .failed, reason: "\(error)")
        }
    }
}
