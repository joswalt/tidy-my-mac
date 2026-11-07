import Foundation
import Testing
import TestSupport
@testable import RuleEngine
import SafetyFloor

func makeRule(_ id: String = "test.rule", targets: [RuleTarget], action: RuleAction = .delete, category: RuleCategory = .cache,
              risk: RuleRisk = .safe, status: RuleStatus = .verified, privilege: RulePrivilege = .user, fda: Bool = false,
              conditions: RuleConditions? = nil, guards: RuleGuards? = nil, macOS: MacOSRange? = nil) -> CleanRule {
    CleanRule(id: id, title: "Test", module: .cleanup, category: category, risk: risk, removes: "x", keeps: "y", notes: nil,
              targets: targets, conditions: conditions, guards: guards, action: action, operationId: nil, privilege: privilege,
              zone: privilege == .helper ? .systemCaches : nil, needsFullDiskAccess: fda, macOS: macOS, status: status,
              source: RuleSource(origin: "own", license: "own", ref: nil, changes: nil), evidence: ["test"], reviewed: nil)
}

struct ScannerTests {
    func scanner(_ t: TestHome, guards: FakeGuards = FakeGuards(), fda: Bool = true) -> RuleScanner {
        RuleScanner(home: t.home, floor: ProtectedFloor(home: t.home), guards: guards, hasFullDiskAccess: fda)
    }

    @Test func ruleStates() throws {
        let t = try TestHome("states")
        defer { t.cleanUp() }
        let target = [RuleTarget(root: ruleRoot("Library/Caches"), match: .children)]
        let s = scanner(t, fda: false)
        #expect(s.scan(makeRule(targets: target, fda: true)).state == .needsFullDiskAccess)
        #expect(s.scan(makeRule(targets: target, privilege: .helper)).state == .requiresHelper)
        #expect(s.scan(makeRule(targets: target, macOS: MacOSRange(min: "99.0", max: nil))).state == .notForThisMacOS)
        #expect(s.scan(makeRule(targets: target, macOS: MacOSRange(min: "10.0", max: "11.0"))).state == .notForThisMacOS)
        #expect(s.scan(makeRule(targets: target, macOS: MacOSRange(min: "14.0", max: nil))).state == .scanned)
    }

    @Test func guards() throws {
        let t = try TestHome("guards")
        defer { t.cleanUp() }
        try t.file("Library/Caches/com.example.A/x")
        try t.file("Library/Caches/com.example.B/x")
        let target = [RuleTarget(root: ruleRoot("Library/Caches"), match: .children)]
        let xcode = makeRule(targets: target, guards: RuleGuards(appsNotRunning: ["com.apple.dt.Xcode"], processesNotRunning: nil, skipIfOwnerAppRunning: nil, onlyIfAppMissing: nil))
        #expect(scanner(t, guards: FakeGuards(running: ["com.apple.dt.Xcode"])).scan(xcode).state == .blocked("com.apple.dt.Xcode is running"))
        #expect(scanner(t).scan(xcode).candidates.count == 2)
        // A guard that can't be checked skips rather than guesses.
        if case .blocked = scanner(t, guards: FakeGuards(failing: true)).scan(xcode).state {} else { Issue.record("should block") }

        let owner = makeRule(targets: target, guards: RuleGuards(appsNotRunning: nil, processesNotRunning: nil, skipIfOwnerAppRunning: true, onlyIfAppMissing: nil))
        let r = scanner(t, guards: FakeGuards(running: ["com.example.a"])).scan(owner)
        #expect(r.candidates.map(\.name) == ["com.example.B"])
        #expect(r.skipped.map { ($0.path as NSString).lastPathComponent } == ["com.example.A"])
        let failing = scanner(t, guards: FakeGuards(failing: true)).scan(owner)
        #expect(failing.candidates.isEmpty && failing.skipped.count == 2)

        let missing = makeRule(targets: target, guards: RuleGuards(appsNotRunning: nil, processesNotRunning: ["ollama"], skipIfOwnerAppRunning: nil, onlyIfAppMissing: "com.example.Tool"))
        #expect(scanner(t, guards: FakeGuards(processes: ["ollama"])).scan(missing).state == .blocked("ollama is running"))
        #expect(scanner(t, guards: FakeGuards(installed: ["com.example.Tool"])).scan(missing).state == .blocked("com.example.Tool is installed"))
    }

    @Test func symlinksAreNeverFollowed() throws {
        let t = try TestHome("symlinks")
        defer { t.cleanUp() }
        try t.file("Documents/precious/file")
        try t.file("Library/Containers/real/Data/Library/Caches/blob")
        // A container that is a symlink into Documents: the wildcard must not pass through it.
        try t.symlink("Library/Containers/evil", to: t.path("Documents"))
        try t.folder("Documents/Data/Library/Caches")
        try t.file("Documents/Data/Library/Caches/victim")
        // A `self` target that is a symlink.
        try t.symlink(".ollama/models", to: t.path("Documents/precious"))

        let s = scanner(t)
        let containers = s.scan(makeRule(targets: [RuleTarget(root: ruleRoot("Library/Containers/*/Data/Library/Caches"), match: .children)]))
        #expect(containers.candidates.map(\.name) == ["blob"])
        let selfRule = s.scan(makeRule(targets: [RuleTarget(root: ruleRoot(".ollama/models"), match: .self)], action: .trash, category: .aiModel, risk: .risky))
        #expect(selfRule.candidates.isEmpty)
        #expect(selfRule.skipped.first?.reason == "it is a symbolic link")
    }

    @Test func conditions() throws {
        let t = try TestHome("conditions")
        defer { t.cleanUp() }
        try t.file("Library/Logs/old/a", size: 10)
        try t.setModified("Library/Logs/old/a", daysAgo: 40)
        try t.setModified("Library/Logs/old", daysAgo: 40)
        try t.file("Library/Logs/new/a", size: 10)
        try t.file("Library/Logs/big/a", size: 200_000)
        try t.setModified("Library/Logs/big/a", daysAgo: 40)
        try t.setModified("Library/Logs/big", daysAgo: 40)
        try t.file("Library/Logs/skipme.log")
        let target = [RuleTarget(root: ruleRoot("Library/Logs"), match: .children)]
        let aged = scanner(t).scan(makeRule(targets: target, category: .log,
            conditions: RuleConditions(minAgeDays: 30, minSizeBytes: nil, excludeNames: ["SKIP*"], owner: .currentUser, launchProgramMissing: nil)))
        #expect(Set(aged.candidates.map(\.name)) == ["old", "big"])
        let big = scanner(t).scan(makeRule(targets: target, category: .log,
            conditions: RuleConditions(minAgeDays: nil, minSizeBytes: 100_000, excludeNames: nil, owner: nil, launchProgramMissing: nil)))
        #expect(big.candidates.map(\.name) == ["big"])
        let rootOwned = scanner(t).scan(makeRule(targets: target, category: .log,
            conditions: RuleConditions(minAgeDays: nil, minSizeBytes: nil, excludeNames: nil, owner: .root, launchProgramMissing: nil)))
        #expect(rootOwned.candidates.isEmpty)
    }

    @Test func lockedAndKindFilters() throws {
        let t = try TestHome("locked")
        defer { t.cleanUp() }
        try t.file("Library/Caches/app/locked")
        try t.lock("Library/Caches/app/locked")
        try t.file("Library/Caches/file.bin")
        let s = scanner(t)
        let any = s.scan(makeRule(targets: [RuleTarget(root: ruleRoot("Library/Caches"), match: .children)]))
        #expect(any.candidates.map(\.name) == ["file.bin"])
        #expect(any.skipped.first?.reason == "it contains a locked item")
        let dirs = s.scan(makeRule(targets: [RuleTarget(root: ruleRoot("Library/Caches"), match: .children, kind: .directory)]))
        #expect(dirs.candidates.isEmpty)
    }

    @Test func floorBlocksRuleItems() throws {
        let t = try TestHome("floor")
        defer { t.cleanUp() }
        try t.file("Library/Application Support/TidyMyMac/RunLog/x.jsonl")
        try t.file("Library/Application Support/Other/x")
        let r = scanner(t).scan(makeRule(targets: [RuleTarget(root: ruleRoot("Library/Application Support"), match: .children)], action: .trash, category: .developer, risk: .caution))
        #expect(r.candidates.map(\.name) == ["Other"])
        #expect(r.skipped.first?.reason.hasPrefix("protected") == true)
    }
}

struct SizerTests {
    @Test func hardLinksAndClonesCountOnce() throws {
        let t = try TestHome("sizer")
        defer { t.cleanUp() }
        try t.file("Documents/original.bin", size: 300_000)
        try t.hardLink("Library/Caches/a/hardlink.bin", to: "Documents/original.bin")
        try t.hardLink("Library/Caches/b/hardlink.bin", to: "Documents/original.bin")
        try t.file("Library/Caches/c/source.bin", size: 300_000)
        try t.clone("Library/Caches/d/clone.bin", of: "Library/Caches/c/source.bin")

        let sizer = Sizer()
        let a = sizer.measure(t.path("Library/Caches/a")).allocatedBytes
        let b = sizer.measure(t.path("Library/Caches/b")).allocatedBytes
        #expect(a > 290_000)
        #expect(b < 10_000, "second hard link must not count again")
        let c = sizer.measure(t.path("Library/Caches/c")).allocatedBytes
        let d = sizer.measure(t.path("Library/Caches/d")).allocatedBytes
        #expect(c > 290_000)
        #expect(d < 10_000, "a clone of an already-counted file must not count again")
    }
}
