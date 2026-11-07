import Foundation
import Testing
import TestSupport
@testable import RuleEngine
import RunLog
import SafetyFloor

struct FakeUnloader: LaunchItemUnloader {
    final class Calls: @unchecked Sendable { var paths: [String] = [] }
    let calls = Calls()
    func unload(plist path: String, userID: UInt32) throws { calls.paths.append(path) }
}

struct CleanupEngineTests {
    static let rules = try! RuleLoader.load(from: RepoPaths.rules, version: 7)

    func context(_ t: TestHome, unloader: LaunchItemUnloader? = nil) -> CleanupContext {
        CleanupContext(home: t.home, rules: Self.rules, guards: FakeGuards(), hasFullDiskAccess: false,
                       trash: HomeTrash(home: t.home), unloader: unloader, appVersion: "1.0 (7)")
    }

    @Test func smartCareNeverIncludesRiskyRules() throws {
        let t = try TestHome("sc-rules")
        defer { t.cleanUp() }
        let c = context(t)
        #expect(c.smartCareRules.allSatisfy { $0.risk != .risky })
        #expect(c.cleanupRules.contains { $0.risk == .risky })
    }

    @Test func selectionRules() throws {
        let t = try TestHome("selection")
        defer { t.cleanUp() }
        try t.file("Library/Caches/com.example.A/x", size: 5000)
        try t.file(".ollama/models/blob", size: 5000)
        let engine = CleanupEngine(context: context(t))
        let report = engine.scan(engine.context.cleanupRules, ignore: IgnoreList())
        let all = report.candidates
        #expect(Selection.defaults(for: all).ids.isEmpty, "experimental rules start unticked")
        var sel = Selection()
        sel.setGroup(all, true)
        #expect(sel.selected(from: all).allSatisfy { $0.risk != .risky }, "select-all skips risky items")
        let risky = try #require(all.first { $0.risk == .risky })
        sel.toggle(risky)
        #expect(sel.contains(risky))
        #expect(sel.state(of: all) == .all)
        sel.setGroup(all, false)
        #expect(sel.state(of: all) == .none)
    }

    @Test func summaryLine() {
        func cand(_ bytes: Int64, _ action: RuleAction) -> Candidate {
            Candidate(ruleID: "r", path: "/x/\(bytes)\(action)", root: "/x", identity: ItemIdentity(device: 1, inode: UInt64(bytes)), isDirectory: false,
                      allocatedBytes: bytes, newestModification: Date(), action: action, risk: .safe, status: .verified)
        }
        let s = CleanupSummary([cand(1_000_000, .trash), cand(2_000_000, .delete), cand(3_000_000, .delete)])
        #expect(s.itemCount == 3 && s.trashBytes == 1_000_000 && s.deleteBytes == 5_000_000)
        #expect(s.line.contains("3 items") && s.line.contains("to Trash") && s.line.contains("deleted permanently"))
        #expect(CleanupSummary([]).line == "Nothing selected")
        #expect(!CleanupSummary([cand(10, .delete)]).line.contains("Trash"))
    }

    @Test func ignoreListNarrowsAndPersists() throws {
        let t = try TestHome("ignore")
        defer { t.cleanUp() }
        try t.file("Library/Caches/com.example.A/x")
        try t.file("Library/Caches/com.example.B/x")
        try t.file("Library/Logs/app.log")
        let engine = CleanupEngine(context: context(t))
        var list = IgnoreList()
        list.add(.init(kind: .path, value: t.path("Library/Caches/com.example.A")))
        list.add(.init(kind: .ruleID, value: "log.user"))
        list.add(.init(kind: .ruleID, value: "log.user"))
        #expect(list.entries.count == 2)
        let names = Set(engine.scan(engine.context.cleanupRules, ignore: list).candidates.map(\.name))
        #expect(names == ["com.example.B"])

        let store = engine.context.ignoreStore
        try store.save(list)
        #expect(try store.load() == list)
        #expect(PathNormalizer.isInside(store.url.path, t.home.tidySupport.path))
        list.remove(.init(kind: .ruleID, value: "log.user"))
        #expect(list.entries.count == 1)
    }

    @Test func dryRunThenRealRunThenRestore() throws {
        let t = try TestHome("engine-run")
        defer { t.cleanUp() }
        try t.file("Library/Caches/com.example.A/x", size: 5000)
        try t.file("Downloads/Tool.dmg", size: 5000)
        let engine = CleanupEngine(context: context(t))
        let all = engine.scan(engine.context.cleanupRules, ignore: IgnoreList()).candidates
        #expect(all.count == 2)

        let dry = try engine.run(all, module: "cleanup", dryRun: true)
        #expect(dry.record.header.dryRun && dry.outcome.done.count == 2)
        #expect(FileStatus.lstat(t.path("Downloads/Tool.dmg")) != nil)

        let real = try engine.run(all, module: "cleanup", dryRun: false)
        #expect(real.record.header.ruleSetVersion == 7)
        #expect(real.outcome.done.count == 2)
        #expect(RunLogReader.runs(in: t.home.tidyRunLogs).count == 2)

        let restorer = Restorer(home: t.home)
        let trashed = try #require(real.record.items.first { $0.action == .trash })
        let deleted = try #require(real.record.items.first { $0.action == .delete })
        #expect(restorer.check(deleted) == .notTrashed)
        #expect(restorer.restore(trashed) == .restored)
        #expect(FileStatus.lstat(t.path("Downloads/Tool.dmg")) != nil)
        #expect(restorer.restore(trashed) == .notInTrash)
    }

    @Test func restoreRefusals() throws {
        let t = try TestHome("restore")
        defer { t.cleanUp() }
        try t.file(".Trash/a.txt")
        try t.file("Documents/elsewhere.txt")
        try t.file("Downloads/a.txt")
        let r = Restorer(home: t.home)
        func item(_ path: String, _ trash: String?) -> RunItem {
            RunItem(ruleID: "x", path: path, allocatedBytes: 1, action: .trash, result: .done, trashPath: trash)
        }
        #expect(r.check(item(t.path("Downloads/a.txt"), t.path(".Trash/a.txt"))) == .originalTaken)
        #expect(r.check(item(t.path("Gone/a.txt"), t.path(".Trash/a.txt"))) == .parentMissing)
        // A log line can't turn restore into "move any file anywhere".
        #expect(r.check(item(t.path("Downloads/b.txt"), t.path("Documents/elsewhere.txt"))) == .notInTrash)
        #expect(r.check(RunItem(ruleID: "x", path: "/p", allocatedBytes: 1, action: .trash, result: .done, trashPath: t.path(".Trash/a.txt"), helperLedgerID: "L1")) == .needsHelper)
    }

    @Test func launchAgentsAreUnloadedBeforeTrashing() throws {
        let t = try TestHome("unload")
        defer { t.cleanUp() }
        let plist: [String: Any] = ["Label": "com.example.gone", "Program": t.path("Applications/Gone.app/Contents/MacOS/Gone")]
        try t.file("Library/LaunchAgents/com.example.gone.plist", contents: try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0))
        let unloader = FakeUnloader()
        let engine = CleanupEngine(context: context(t, unloader: unloader))
        let all = engine.scan(engine.context.cleanupRules, ignore: IgnoreList()).candidates
        #expect(all.map(\.ruleID) == ["launch.user.broken"])
        _ = try engine.run(all, module: "cleanup", dryRun: true)
        #expect(unloader.calls.paths.isEmpty, "a dry run unloads nothing")
        _ = try engine.run(all, module: "cleanup", dryRun: false)
        #expect(unloader.calls.paths == [t.path("Library/LaunchAgents/com.example.gone.plist")])
    }
}

struct SelectionIsolationTests {
    @Test func tickingOneItemNeverTicksItsNeighbours() {
        func cand(_ n: String, helper: Bool) -> Candidate {
            Candidate(ruleID: "cache.system", path: HelperZone.systemCaches.roots[0] + "/" + n, root: HelperZone.systemCaches.roots[0], identity: ItemIdentity(device: 0, inode: 0),
                      isDirectory: true, allocatedBytes: 1, newestModification: Date(), action: .delete, risk: .caution,
                      status: .experimental, helperHandle: helper ? UUID() : nil)
        }
        let items = ["TidyCanary-A", "TidyCanary-B", "com.example"].map { cand($0, helper: true) }
        var sel = Selection.defaults(for: items)
        #expect(sel.ids.isEmpty, "experimental helper items start unticked")
        sel.set(items[0], true)
        #expect(sel.selected(from: items).map(\.name) == ["TidyCanary-A"])
        #expect(sel.state(of: items) == .some)
    }
}
