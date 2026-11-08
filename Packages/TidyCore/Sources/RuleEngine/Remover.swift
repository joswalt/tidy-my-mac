import Foundation
import RunLog
import SafetyFloor

/// Where trashed items go. The app uses the system Trash; tests use the fixture home's Trash.
public protocol TrashMover: Sendable {
    /// Moves the item to the Trash and returns where it ended up.
    func moveToTrash(_ path: String) throws -> String
}

/// Runs a reviewed selection: the only RuleEngine code allowed to remove files (spec 017 §2).
/// Before each item it re-checks everything the scan checked, because the scan may be minutes
/// old (spec 006 §5.4): same item (device + inode), not a symlink, still inside its root,
/// not on the floor, guards still pass. Anything that changed is skipped and logged.
public struct Remover: Sendable {
    public let scanner: RuleScanner
    public let trash: TrashMover
    /// Unloads launch agents before trashing them; nil in tests (they never call launchctl).
    public let unloader: LaunchItemUnloader?

    public init(scanner: RuleScanner, trash: TrashMover, unloader: LaunchItemUnloader? = nil) {
        self.scanner = scanner
        self.trash = trash
        self.unloader = unloader
    }

    public struct Outcome: Sendable {
        public var done: [RunItem] = []
        public var skipped: [RunItem] = []
        public var failed: [RunItem] = []
        public var all: [RunItem] { done + skipped + failed }

        public init() {}

        /// Files an item under done, skipped or failed by its result.
        public mutating func add(_ item: RunItem) {
            switch item.result {
            case .done: done.append(item)
            case .skipped: skipped.append(item)
            case .failed: failed.append(item)
            }
        }
    }

    /// Removes (or with `dryRun`, only reports) each selected candidate, logging every item.
    public func run(_ selection: [Candidate], rules: RuleSet, log: RunLogWriter, dryRun: Bool) throws -> Outcome {
        var outcome = Outcome()
        for c in selection where !c.viaHelper {
            let item = process(c, rule: rules.cleanRule(c.ruleID), dryRun: dryRun)
            try log.append(item)
            switch item.result {
            case .done: outcome.done.append(item)
            case .skipped: outcome.skipped.append(item)
            case .failed: outcome.failed.append(item)
            }
        }
        return outcome
    }

    func process(_ c: Candidate, rule: CleanRule?, dryRun: Bool) -> RunItem {
        let action: RunAction = c.action == .delete ? .delete : .trash
        func skip(_ reason: String) -> RunItem {
            RunItem(ruleID: c.ruleID, path: c.path, allocatedBytes: c.allocatedBytes, action: action, result: .skipped, reason: reason)
        }
        guard let rule else { return skip("its rule is no longer in the rule set") }
        guard !c.viaHelper else { return skip("removed through the admin helper") }
        guard c.action != .operation else { return skip("operations run elsewhere") }

        // Fresh checks (spec 006 §5.4).
        let status: FileStatus
        do { status = try Containment.validate(item: c.path, root: c.root) } catch {
            return skip(error.description)
        }
        if status.identity != c.identity { return skip("the item was replaced since the scan") }
        if case .protected(let why) = scanner.floor.verdict(for: c.path, context: .rule) { return skip("protected: \(why)") }
        if let blocked = scanner.ruleLevelGuard(rule) { return skip(blocked) }
        if rule.guards?.skipIfOwnerAppRunning == true {
            do {
                if try scanner.guards.runningBundleIDs().map(PathNormalizer.fold).contains(PathNormalizer.fold(c.name)) {
                    return skip("\(c.name) is running")
                }
            } catch {
                return skip("\(error)")  // A guard that can't be checked skips (spec 006 §3.1).
            }
        }
        let m = Sizer().measure(c.path)
        if m.crossesVolume { return skip("it contains another volume") }
        if m.containsLockedItem { return skip("it contains a locked item") }
        if m.containsMediaLibrary { return skip("it contains a media library") }

        if dryRun {
            return RunItem(ruleID: c.ruleID, path: c.path, allocatedBytes: c.allocatedBytes, action: action, result: .done)
        }
        do {
            switch c.action {
            case .delete:
                try Self.removeTree(c.path, device: status.device)
                return RunItem(ruleID: c.ruleID, path: c.path, allocatedBytes: c.allocatedBytes, action: .delete, result: .done)
            case .trash:
                try TestFence.check(c.path)
                if rule.category == .launchItem, let unloader {
                    try unloader.unload(plist: c.path, userID: scanner.home.userID)
                }
                let dest = try trash.moveToTrash(c.path)
                return RunItem(ruleID: c.ruleID, path: c.path, allocatedBytes: c.allocatedBytes, action: .trash, result: .done, trashPath: dest)
            case .operation:
                return skip("operations run elsewhere")
            }
        } catch {
            return RunItem(ruleID: c.ruleID, path: c.path, allocatedBytes: c.allocatedBytes, action: action, result: .failed,
                           reason: "\(error)")
        }
    }

    public struct RemoveError: Error, CustomStringConvertible {
        public let path: String
        public let message: String
        public var description: String { "\(message): \(path)" }
    }

    /// Permanently deletes a file or folder tree without following symlinks or leaving the volume.
    static func removeTree(_ path: String, device: Int32) throws {
        try TestFence.check(path)
        guard let st = FileStatus.lstat(path) else { throw RemoveError(path: path, message: "missing") }
        if st.device != device { throw RemoveError(path: path, message: "on another volume") }
        if st.isDirectory {
            for name in try FileManager.default.contentsOfDirectory(atPath: path) {
                try removeTree(path + "/" + name, device: device)
            }
            if Darwin.rmdir(path) != 0 { throw RemoveError(path: path, message: String(cString: strerror(errno))) }
        } else {
            if Darwin.unlink(path) != 0 { throw RemoveError(path: path, message: String(cString: strerror(errno))) }
        }
    }
}

/// Emptying the Trash bins (build spec §6.4): permanent, so only what the review listed, only
/// items the user owns, re-checked first. Root-owned items TidyMyMac's helper trashed are emptied
/// by the helper (the app passes those separately); anything else is left for Finder.
public enum TrashEmptier {
    public static func empty(_ items: [Candidate], home: Home, floor: ProtectedFloor, dryRun: Bool) -> [RunItem] {
        items.map { c in
            func item(_ r: RunResult, _ why: String? = nil) -> RunItem {
                RunItem(ruleID: TrashBins.ruleID, path: c.path, allocatedBytes: c.allocatedBytes, action: .delete, result: r, reason: why)
            }
            let st: FileStatus
            do { st = try Containment.validate(item: c.path, root: c.root) } catch {
                if (error as? ContainmentError) == .symlinkedItem, let link = FileStatus.lstat(c.path), link.identity == c.identity {
                    st = link  // a symlink in the Trash is removed as a link
                } else {
                    return item(.skipped, "\(error)")
                }
            }
            if st.identity != c.identity { return item(.skipped, "the item was replaced since the scan") }
            if case .protected(let why) = floor.verdict(for: c.path, context: .manualPick) { return item(.skipped, "protected: \(why)") }
            if st.userID != home.userID { return item(.skipped, "Empty in Finder (needs your password)") }
            let m = Sizer().measure(c.path)
            if m.containsLockedItem { return item(.skipped, "it contains a locked item") }
            if m.containsMediaLibrary { return item(.skipped, "it contains a media library") }
            if m.crossesVolume { return item(.skipped, "it contains another volume") }
            if dryRun { return item(.done) }
            do {
                try Remover.removeTree(c.path, device: st.device)
                return item(.done)
            } catch {
                return item(.failed, "\(error)")
            }
        }
    }
}
