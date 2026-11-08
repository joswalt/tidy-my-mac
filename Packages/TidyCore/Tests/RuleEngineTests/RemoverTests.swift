import Foundation
import Testing
import TestSupport
@testable import RuleEngine
import RunLog
import SafetyFloor

struct RemoverTests {
    struct Setup {
        let t: TestHome
        let scanner: RuleScanner
        let remover: Remover
        let set: RuleSet
        let rule: CleanRule
        let trashRule: CleanRule
        let log: RunLogWriter
    }

    func setUp(_ label: String, guards: FakeGuards = FakeGuards()) throws -> Setup {
        let t = try TestHome(label)
        let scanner = RuleScanner(home: t.home, floor: ProtectedFloor(home: t.home), guards: guards, hasFullDiskAccess: true)
        let rule = makeRule("test.delete", targets: [RuleTarget(root: ruleRoot("Library/Caches"), match: .children)],
                            guards: RuleGuards(appsNotRunning: ["com.example.Guarded"], processesNotRunning: nil, skipIfOwnerAppRunning: nil, onlyIfAppMissing: nil))
        let trashRule = makeRule("test.trash", targets: [RuleTarget(root: ruleRoot("Library/Developer/Xcode/Archives"), match: .children)],
                                 action: .trash, category: .developer, risk: .risky)
        var set = RuleSet(version: 1)
        set.cleanRules = [rule, trashRule]
        let log = try RunLogWriter(directory: t.home.tidyRunLogs, header: RunHeader(module: "cleanup", appVersion: "test", ruleSetVersion: 1, dryRun: false))
        return Setup(t: t, scanner: scanner, remover: Remover(scanner: scanner, trash: HomeTrash(home: t.home)), set: set, rule: rule, trashRule: trashRule, log: log)
    }

    @Test func dryRunChangesNothing() throws {
        let s = try setUp("dry")
        defer { s.t.cleanUp() }
        try s.t.file("Library/Caches/app/a")
        let before = Snapshot(of: s.t.home.root.appendingPathComponent("Library/Caches").path)
        let c = s.scanner.scan(s.rule).candidates
        let out = try s.remover.run(c, rules: s.set, log: s.log, dryRun: true)
        #expect(out.done.count == 1)
        #expect(Snapshot(of: s.t.home.root.appendingPathComponent("Library/Caches").path).entries == before.entries)
    }

    @Test func deleteAndTrash() throws {
        let s = try setUp("act")
        defer { s.t.cleanUp() }
        try s.t.file("Library/Caches/app/a")
        try s.t.symlink("Library/Caches/app/link-to-docs", to: s.t.path("Documents"))
        try s.t.file("Documents/keep.txt")
        try s.t.file("Library/Developer/Xcode/Archives/2026-11-07/App.xcarchive/Info.plist")
        let archive = s.t.path("Library/Developer/Xcode/Archives/2026-11-07")
        let inode = FileStatus.lstat(archive)!.inode

        let c = s.scanner.scan([s.rule, s.trashRule]).candidates
        let out = try s.remover.run(c, rules: s.set, log: s.log, dryRun: false)
        try s.log.finish()
        #expect(out.done.count == 2)
        #expect(FileStatus.lstat(s.t.path("Library/Caches/app")) == nil)
        #expect(FileStatus.lstat(s.t.path("Documents/keep.txt")) != nil, "deleting a symlink must not touch its target")
        let trashed = try #require(out.done.first { $0.action == .trash }?.trashPath)
        #expect(FileStatus.lstat(trashed)?.inode == inode)
        #expect(PathNormalizer.isInside(trashed, s.t.home.trash.path))
    }

    @Test func foldersContainingAMediaLibraryAreSkipped() throws {
        let s = try setUp("media-library")
        defer { s.t.cleanUp() }
        try s.t.file("Library/Caches/holder/a")
        try s.t.file("Library/Caches/plain/a")
        let c = s.scanner.scan(s.rule).candidates
        #expect(c.count == 2)
        // After the scan, a media library appears inside one of them.
        try s.t.file("Library/Caches/holder/Photos Library.photoslibrary/database/db")
        let out = try s.remover.run(c, rules: s.set, log: s.log, dryRun: false)
        #expect(out.done.map(\.path) == [s.t.path("Library/Caches/plain")])
        #expect(out.skipped.first?.reason == "it contains a media library")
        #expect(FileStatus.lstat(s.t.path("Library/Caches/holder/Photos Library.photoslibrary/database/db")) != nil)

        // And a scan offers nothing that contains one.
        let again = s.scanner.scan(s.rule)
        #expect(again.candidates.isEmpty)
        #expect(again.skipped.contains { $0.reason == "it contains a media library" })
    }

    @Test func midRunChangesAreSkipped() throws {
        var guards = FakeGuards()
        let s = try setUp("midrun", guards: guards)
        defer { s.t.cleanUp() }
        try s.t.file("Library/Caches/swapped/a")
        try s.t.file("Library/Caches/replaced")
        try s.t.file("Library/Caches/gets-locked/a")
        try s.t.file("Documents/target/x")
        let c = s.scanner.scan(s.rule).candidates
        #expect(c.count == 3)

        // Between scan and run: a folder becomes a symlink, a file gets a new inode, a file gets locked.
        try s.t.remove("Library/Caches/swapped")
        try s.t.symlink("Library/Caches/swapped", to: s.t.path("Documents/target"))
        try s.t.remove("Library/Caches/replaced")
        try s.t.file("Library/Caches/replaced", size: 10)
        try s.t.lock("Library/Caches/gets-locked/a")

        let out = try s.remover.run(c, rules: s.set, log: s.log, dryRun: false)
        #expect(out.done.isEmpty)
        #expect(out.skipped.count == 3)
        #expect(FileStatus.lstat(s.t.path("Documents/target/x")) != nil)

        // An app named in a guard starts between scan and run.
        try s.t.file("Library/Caches/later/a")
        let c2 = s.scanner.scan(s.rule).candidates
        guards.running = ["com.example.Guarded"]
        let blocked = Remover(scanner: RuleScanner(home: s.t.home, floor: s.scanner.floor, guards: guards, hasFullDiskAccess: true),
                              trash: HomeTrash(home: s.t.home))
        let out2 = try blocked.run(c2.filter { $0.name == "later" }, rules: s.set, log: s.log, dryRun: false)
        #expect(out2.skipped.first?.reason == "com.example.Guarded is running")
        #expect(FileStatus.lstat(s.t.path("Library/Caches/later/a")) != nil)
    }
}
