import Foundation
import RuleEngine
import RunLog
import SafetyFloor
import Testing
import TestSupport

/// The core property (spec 017 §4.1): a run removes exactly the items selected, in the way the
/// review promised (Trash or delete), and nothing else.
struct SnapshotDiffTests {
    static let rules = try! RuleLoader.load(from: RepoPaths.rules, version: 1)

    // MARK: Fixture

    /// Junk for every v1 user-level rule.
    static let junk: [(String, Int)] = [
        ("Library/Caches/com.example.Editor/Cache.db", 4096),
        ("Library/Caches/com.example.Big/blob", 300_000),
        ("Library/Containers/com.example.Sandboxed/Data/Library/Caches/blob", 2048),
        ("Library/Logs/DiagnosticReports/App.crash", 512),
        ("Library/Logs/com.example.log", 512),
        ("Library/Developer/Xcode/DerivedData/App-abc/Build/x", 8192),
        ("Library/Developer/Xcode/UserData/Previews/Simulator Devices/x", 1024),
        ("Library/Developer/Xcode/iOS DeviceSupport/iPhone 18.0/Symbols/x", 1024),
        ("Library/Developer/Xcode/Archives/2026-11-07/App.xcarchive/Info.plist", 256),
        (".ollama/models/blobs/sha256-1", 4096),
        (".lmstudio/models/org/model.gguf", 4096),
        (".cache/huggingface/hub/models--org--name/blobs/x", 4096),
        ("Library/Application Support/MobileSync/Backup/00008110-ABC/Manifest.db", 4096),
        ("Downloads/Tool-1.2.dmg", 4096),
    ]

    /// Files that must come through every run byte-identical.
    static let tripwires = [
        "Documents/tw.txt", "Desktop/tw.txt", "Pictures/tw.jpg", "Movies/tw.mov", "Music/tw.m4a",
        "Library/Keychains/login.keychain-db", "Library/Mobile Documents/com~apple~CloudDocs/tw.txt",
        "Library/CloudStorage/Dropbox/tw.txt", "Library/Mail/V10/tw.emlx",
        "Pictures/Photos Library.photoslibrary/database/tw.db", "Applications/Foo.app/Contents/Info.plist",
        "Library/Application Support/TidyMyMac/tw.json", "Library/Logs/TidyMyMac/tw.log",
        "Library/Caches/com.apple.something/tw", "Library/Application Support/com.apple.something/tw",
        "Library/Containers/com.apple.Notes/Data/Library/Caches/tw", "Library/Caches/com.example.Locked/locked",
        "Downloads/report.pdf", "Documents/linked.bin", "Documents/cloned.bin",
    ]

    static func build(_ t: TestHome) throws {
        for (p, size) in junk { try t.file(p, size: size) }
        for p in tripwires { try t.file(p, size: p.hasSuffix(".bin") ? 200_000 : 128) }
        // A broken login item and a working one.
        try writeLaunchAgent(t, "Library/LaunchAgents/com.example.gone.plist", program: t.path("Applications/Gone.app/Contents/MacOS/Gone"))
        try t.file("bin/tool")
        try writeLaunchAgent(t, "Library/LaunchAgents/com.example.present.plist", program: t.path("bin/tool"))
        // Links and clones that lead out of cache folders into protected ones.
        try t.symlink("Library/Caches/escape", to: t.path("Documents"))
        try t.symlink("Library/Caches/com.example.Editor/docs-link", to: t.path("Documents"))
        try t.hardLink("Library/Caches/com.example.Links/hard.bin", to: "Documents/linked.bin")
        try t.clone("Library/Caches/com.example.Clones/clone.bin", of: "Documents/cloned.bin")
        try t.lock("Library/Caches/com.example.Locked/locked")
    }

    static func writeLaunchAgent(_ t: TestHome, _ path: String, program: String) throws {
        let plist: [String: Any] = ["Label": (path as NSString).lastPathComponent, "Program": program]
        try t.file(path, contents: try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0))
    }

    static func scanner(_ t: TestHome, guards: FakeGuards = FakeGuards()) -> RuleScanner {
        RuleScanner(home: t.home, floor: ProtectedFloor(home: t.home, additions: rules.floorAdditions(home: t.home)),
                    guards: guards, hasFullDiskAccess: true)
    }

    static func run(_ t: TestHome, _ selection: [Candidate], scanner: RuleScanner) throws -> (Remover.Outcome, RunRecord) {
        let log = try RunLogWriter(directory: t.home.tidyRunLogs,
                                   header: RunHeader(module: "smartCare", appVersion: "test", ruleSetVersion: 1, dryRun: false))
        let outcome = try Remover(scanner: scanner, trash: HomeTrash(home: t.home)).run(selection, rules: rules, log: log, dryRun: false)
        try log.finish()
        return (outcome, try RunLogReader.read(log.fileURL))
    }

    // MARK: The property

    /// Asserts the run removed exactly `removed` (as their candidates promised) and nothing else.
    static func assertProperty(_ t: TestHome, before: Snapshot, after: Snapshot, removed: [Candidate],
                               outcome: Remover.Outcome, record: RunRecord, sourceLocation: SourceLocation = #_sourceLocation) {
        let root = t.home.root.path
        func rel(_ p: String) -> String { p.hasPrefix(root + "/") ? String(p.dropFirst(root.count + 1)) : p }
        let removedRel = removed.map { rel($0.path) }
        func underRemoved(_ p: String) -> Bool { removedRel.contains { p == $0 || p.hasPrefix($0 + "/") } }
        func isNew(_ p: String) -> Bool {
            let runLog = "Library/Application Support/TidyMyMac/RunLog"
            return p == ".Trash" || p.hasPrefix(".Trash/") || p.hasPrefix(runLog) || runLog.hasPrefix(p + "/")
        }

        // 1. Removed set == selected set.
        let gone = before.paths.subtracting(after.paths)
        #expect(Set(gone.filter { !underRemoved($0) }).isEmpty, "removed without being selected: \(gone.filter { !underRemoved($0) }.sorted())", sourceLocation: sourceLocation)
        for p in removedRel { #expect(!after.paths.contains(p), "\(p) was selected but is still there", sourceLocation: sourceLocation) }

        // 2. Everything else is untouched (identity, size, mtime, flags, content). Folders that
        // gained or lost a child (parents of removed items, of the Trash or the run log) only
        // keep their identity, since their modification date changes.
        let changedPaths = gone.union(after.paths.subtracting(before.paths))
        for (p, e) in before.entries where !underRemoved(p) {
            guard let now = after.entries[p] else { continue }
            if changedPaths.contains(where: { $0.hasPrefix(p + "/") }) {
                #expect(now.identity == e.identity, "\(p) was replaced", sourceLocation: sourceLocation)
                continue
            }
            #expect(now == e, "\(p) changed", sourceLocation: sourceLocation)
        }
        for p in tripwires { #expect(after.entries[p] == before.entries[p], "tripwire \(p) changed", sourceLocation: sourceLocation) }

        // 3. Nothing appeared except Trash items and the run log.
        let added = after.paths.subtracting(before.paths).filter { !isNew($0) }
        #expect(added.isEmpty, "unexpected new paths: \(added.sorted())", sourceLocation: sourceLocation)

        // 4. Trash items are the same items (same inode); deletes are gone for good.
        for c in removed {
            let item = outcome.done.first { $0.path == c.path }
            #expect(item != nil, "\(c.path) has no done record", sourceLocation: sourceLocation)
            switch c.action {
            case .trash:
                let dest = item?.trashPath ?? ""
                #expect(PathNormalizer.isInside(dest, t.home.trash.path), sourceLocation: sourceLocation)
                #expect(FileStatus.lstat(dest)?.identity == c.identity, "\(c.path) not in the Trash as the same item", sourceLocation: sourceLocation)
            case .delete:
                #expect(item?.trashPath == nil, sourceLocation: sourceLocation)
                #expect(!after.paths.contains { $0.hasPrefix(".Trash/") && $0.hasSuffix("/" + c.name) }, sourceLocation: sourceLocation)
            case .operation: break
            }
        }

        // 5. The run log has exactly one entry per item, with the right rule and action.
        #expect(record.items.count == outcome.all.count, sourceLocation: sourceLocation)
        for c in removed {
            let entries = record.items.filter { $0.path == c.path }
            #expect(entries.count == 1, "\(c.path) logged \(entries.count) times", sourceLocation: sourceLocation)
            #expect(entries.first?.ruleID == c.ruleID, sourceLocation: sourceLocation)
            #expect(entries.first?.action.description == (c.action == .delete ? "delete" : "trash"), sourceLocation: sourceLocation)
            #expect(entries.first?.result == .done, sourceLocation: sourceLocation)
        }
        #expect(!record.isInterrupted, sourceLocation: sourceLocation)
    }

    // MARK: Tests

    @Test func defaultSelectionRemovesNothingWhileRulesAreExperimental() throws {
        let t = try TestHome("e2e-default")
        defer { t.cleanUp() }
        try Self.build(t)
        let s = Self.scanner(t)
        let report = s.scan(Self.rules.cleanRules)
        let selection = report.candidates.filter(\.selectedByDefault)
        #expect(selection.isEmpty)
        let before = Snapshot(of: t.home.root.path)
        let (outcome, record) = try Self.run(t, selection, scanner: s)
        Self.assertProperty(t, before: before, after: Snapshot(of: t.home.root.path), removed: [], outcome: outcome, record: record)
    }

    @Test func everythingSelected() throws {
        let t = try TestHome("e2e-all")
        defer { t.cleanUp() }
        try Self.build(t)
        let s = Self.scanner(t)
        let report = s.scan(Self.rules.cleanRules)
        let selection = report.candidates

        // Every rule found its junk; the dangerous lookalikes were refused at scan time.
        let ids = Set(selection.map(\.ruleID))
        for r in Self.rules.cleanRules where r.action != .operation && r.privilege == .user { #expect(ids.contains(r.id), "\(r.id) found nothing") }
        let names = Set(selection.map(\.name))
        for bad in ["escape", "TidyMyMac", "com.apple.something", "com.example.Locked", "com.example.present.plist", "report.pdf"] {
            #expect(!names.contains(bad), "\(bad) must not be a candidate")
        }
        #expect(Set(report.skipped.map { ($0.path as NSString).lastPathComponent }).isSuperset(of: ["escape", "TidyMyMac", "com.example.Locked"]))

        let before = Snapshot(of: t.home.root.path)
        let (outcome, record) = try Self.run(t, selection, scanner: s)
        #expect(outcome.skipped.isEmpty && outcome.failed.isEmpty, "\(outcome.skipped + outcome.failed)")
        Self.assertProperty(t, before: before, after: Snapshot(of: t.home.root.path), removed: selection, outcome: outcome, record: record)
    }

    @Test func midRunChangesAreSkippedAndLogged() throws {
        let t = try TestHome("e2e-midrun")
        defer { t.cleanUp() }
        try Self.build(t)
        let s = Self.scanner(t)
        let selection = s.scan(Self.rules.cleanRules).candidates

        // Between scan and run: a selected folder becomes a symlink into Documents, a selected
        // file is replaced by a new one, and Xcode starts.
        try t.remove("Library/Caches/com.example.Big")
        try t.symlink("Library/Caches/com.example.Big", to: t.path("Documents"))
        try t.remove("Downloads/Tool-1.2.dmg")
        try t.file("Downloads/Tool-1.2.dmg", size: 99)
        let changed: Set<String> = [t.path("Library/Caches/com.example.Big"), t.path("Downloads/Tool-1.2.dmg")]
        let xcodeRunning = Self.scanner(t, guards: FakeGuards(running: ["com.apple.dt.Xcode"]))

        let before = Snapshot(of: t.home.root.path)
        let (outcome, record) = try Self.run(t, selection, scanner: xcodeRunning)

        let xcodeRules: Set<String> = ["dev.xcode.derived-data", "dev.xcode.previews", "dev.xcode.device-support"]
        let expectSkipped = selection.filter { changed.contains($0.path) || xcodeRules.contains($0.ruleID) }
        #expect(Set(outcome.skipped.map(\.path)) == Set(expectSkipped.map(\.path)))
        for item in outcome.skipped { #expect(item.reason != nil) }
        #expect(record.items.filter { $0.result == .skipped }.count == expectSkipped.count)
        #expect(FileStatus.lstat(t.path("Downloads/Tool-1.2.dmg"))?.size == 99, "the replacement file must be left alone")

        let done = selection.filter { c in !expectSkipped.contains { $0.path == c.path } }
        Self.assertProperty(t, before: before, after: Snapshot(of: t.home.root.path), removed: done, outcome: outcome, record: record)
    }

    // MARK: Random trees

    static let seeds: [UInt64] = ProcessInfo.processInfo.environment["TIDY_LONG_RANDOM"] != nil ? Array(1...200) : [1, 2, 3, 42]

    @Test(arguments: seeds)
    func randomTree(_ seed: UInt64) throws {
        let t = try TestHome("e2e-random-\(seed)")
        defer { t.cleanUp() }
        for p in Self.tripwires.prefix(8) { try t.file(p) }
        var rng = SplitMix(seed: seed)
        let names = ["plain", "with space", "Caf\u{00E9}", "Cafe\u{0301}", "new\nline", String(repeating: "n", count: 240),
                     ".hidden", "UPPER", "dots.in.name", "emoji\u{1F9F9}"]
        func name() -> String { names[Int(rng.next() % UInt64(names.count))] + (rng.next() % 2 == 0 ? "" : "-\(rng.next() % 100)") }
        var dirs = ["Library/Caches/com.example.Random"]
        for _ in 0..<60 {
            let parent = dirs[Int(rng.next() % UInt64(dirs.count))]
            let n = name()
            // Names may collide (NFC and NFD forms are the same name on APFS); collisions are skipped.
            guard FileStatus.lstat(t.path(parent + "/" + n)) == nil else { continue }
            switch rng.next() % 5 {
            case 0: if (try? t.folder(parent + "/" + n)) != nil { dirs.append(parent + "/" + n) }
            case 1: try? t.symlink(parent + "/" + n + "-link", to: t.path(Self.tripwires[Int(rng.next() % 8)]))
            default: _ = try? t.file(parent + "/" + n, size: Int(rng.next() % 5000))
            }
        }
        try t.folder("Library/Caches/com.example.Random")
        try t.file("Library/Caches/top-level-item", size: 100)

        let s = Self.scanner(t)
        let rule = try #require(Self.rules.cleanRule("cache.user.apps"))
        let selection = s.scan([rule]).candidates
        #expect(!selection.isEmpty)
        let before = Snapshot(of: t.home.root.path)
        let (outcome, record) = try Self.run(t, selection, scanner: s)
        #expect(outcome.failed.isEmpty, "\(outcome.failed)")
        Self.assertProperty(t, before: before, after: Snapshot(of: t.home.root.path),
                            removed: selection.filter { c in outcome.done.contains { $0.path == c.path } },
                            outcome: outcome, record: record)
    }
}

/// A tiny seeded generator so random trees are the same on every machine.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
