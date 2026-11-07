import Foundation
import Testing
import TestSupport
@testable import RuleEngine
import RunLog
import SafetyFloor

struct HelperRuleMatcherTests {
    static let rules = try! RuleLoader.load(from: RepoPaths.rules, version: 1)

    func item(_ zone: HelperZone, _ path: String, programExists: Bool? = nil) -> HelperFoundItem {
        HelperFoundItem(handle: UUID(), zone: zone, path: path, allocatedBytes: 100, modified: Date(), isDirectory: true, launchProgramExists: programExists)
    }

    @Test func systemRulesMatchTheirZones() throws {
        let t = try TestHome("helper-rules")
        defer { t.cleanUp() }
        let caches = try #require(Self.rules.cleanRule("cache.system"))
        let found = [item(.systemCaches, HelperZone.systemCaches.roots[0] + "/com.example.x"),
                     item(.systemCaches, HelperZone.systemCaches.roots[0] + "/com.apple.y"),
                     item(.libraryLeftovers, HelperZone.libraryLeftovers.roots[3] + "/com.example.z")]
        let r = HelperRuleMatcher.result(for: caches, items: found, home: t.home)
        #expect(r.candidates.map(\.name) == ["com.example.x"])
        #expect(r.candidates.allSatisfy { $0.viaHelper && $0.action == .delete })

        let launch = try #require(Self.rules.cleanRule("launch.system.broken"))
        let l = HelperRuleMatcher.result(for: launch, items: [
            item(.launchItems, HelperZone.launchItems.roots[1] + "/com.example.gone.plist", programExists: false),
            item(.launchItems, HelperZone.launchItems.roots[0] + "/com.example.ok.plist", programExists: true),
            item(.launchItems, HelperZone.launchItems.roots[0] + "/com.example.unknown.plist", programExists: nil),
        ], home: t.home)
        #expect(l.candidates.map(\.name) == ["com.example.gone.plist"])
        #expect(l.candidates.first?.action == .trash)
    }

    @Test func helperCandidatesNeverReachTheUserRemover() throws {
        let t = try TestHome("helper-skip")
        defer { t.cleanUp() }
        let ctx = CleanupContext(home: t.home, rules: Self.rules, guards: FakeGuards(), hasFullDiskAccess: true,
                                 trash: HomeTrash(home: t.home), unloader: nil, appVersion: "t")
        let c = Candidate(ruleID: "cache.system", path: t.path("Library/Caches/x"), root: t.path("Library/Caches"),
                          identity: ItemIdentity(device: 0, inode: 0), isDirectory: false, allocatedBytes: 1, newestModification: Date(),
                          action: .delete, risk: .caution, status: .experimental, helperHandle: UUID())
        try t.file("Library/Caches/x")
        let extra = RunItem(ruleID: "cache.system", path: "/x", allocatedBytes: 5, action: .delete, result: .done)
        let run = try CleanupEngine(context: ctx).run([c], module: "cleanup", dryRun: false, extraItems: [extra])
        #expect(FileStatus.lstat(t.path("Library/Caches/x")) != nil)
        #expect(run.record.items == [extra] || run.record.items.map(\.path) == ["/x"])
    }
}

struct TrashBinTests {
    @Test func scanAndEmpty() throws {
        let t = try TestHome("trashbins")
        defer { t.cleanUp() }
        try t.file(".Trash/old.zip", size: 5000)
        try t.file(".Trash/folder/a", size: 100)
        try t.symlink(".Trash/link-to-docs", to: t.path("Documents"))
        try t.file("Documents/keep.txt")
        try t.file(".Trash/locked/x")
        try t.lock(".Trash/locked/x")
        // A fake /Volumes with one external Trash for this uid.
        let volumes = t.base.appendingPathComponent("Volumes").path
        let ext = "\(volumes)/Backup/.Trashes/\(t.home.userID)"
        try FileManager.default.createDirectory(atPath: ext, withIntermediateDirectories: true)
        try Data(count: 10).write(to: URL(fileURLWithPath: ext + "/movie.mov"))

        let floor = ProtectedFloor(home: t.home)
        let bins = TrashBins.scan(home: t.home, floor: floor, volumesRoot: volumes)
        #expect(bins.map(\.title) == ["Trash", "Trash on Backup"])
        #expect(Set(bins[0].items.map(\.name)) == ["old.zip", "folder", "link-to-docs", "locked"])
        #expect(bins[1].items.map(\.name) == ["movie.mov"])

        let dry = TrashEmptier.empty(bins[0].items, home: t.home, floor: floor, dryRun: true)
        #expect(dry.filter { $0.result == .done }.count == 3)
        #expect(FileStatus.lstat(t.path(".Trash/old.zip")) != nil)

        let real = TrashEmptier.empty(bins[0].items, home: t.home, floor: floor, dryRun: false)
        let byName = Dictionary(uniqueKeysWithValues: real.map { (($0.path as NSString).lastPathComponent, $0) })
        #expect(byName["old.zip"]?.result == .done && byName["folder"]?.result == .done && byName["link-to-docs"]?.result == .done)
        #expect(byName["locked"]?.result == .skipped)
        #expect(FileStatus.lstat(t.path("Documents/keep.txt")) != nil, "emptying a symlink never touches its target")
        #expect(FileStatus.lstat(t.path(".Trash")) != nil)
    }
}
