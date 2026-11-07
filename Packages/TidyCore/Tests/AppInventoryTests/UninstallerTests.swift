import Foundation
import RuleEngine
import RunLog
import SafetyFloor
import Testing
import TestSupport
@testable import AppInventory

struct FakeSignatures: AppSignatures {
    var applePaths: Set<String> = []
    func isAppleSigned(_ appPath: String) -> Bool { applePaths.contains { appPath.hasSuffix($0) } }
    func teamID(_ appPath: String) -> String? { nil }
}

struct FakeUsage: AppUsage {
    var dates: [String: Date] = [:]
    func lastUsed(_ appPath: String) -> Date? { dates[(appPath as NSString).lastPathComponent] }
}

struct FakeReceipts: PackageReceipts {
    var owning: [String: [String]] = [:]
    var all: [String] = []
    var filesOf: [String: [String]] = [:]
    func packages(owning path: String) -> [String] { owning[(path as NSString).lastPathComponent] ?? [] }
    func allPackages() -> [String] { all }
    func files(of packageID: String) -> [String] { filesOf[packageID] ?? [] }
}

/// The dummy app of spec 017 §4.4: `TidyTestDummy.app`, bundle ID `io.github.joswalt.TidyTest.Dummy`,
/// built into the fixture by the test, with leftovers in every `leftover-location` root.
enum Dummy {
    static let id = "io.github.joswalt.TidyTest.Dummy"
    static let rules = try! RuleLoader.load(from: RepoPaths.rules, version: 1)

    @discardableResult
    static func app(_ t: TestHome, _ relative: String, bundleID: String, name: String? = nil, version: String = "1.0") throws -> String {
        let info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name ?? bundleID, "CFBundleShortVersionString": version,
                                   "CFBundleVersion": "100", "CFBundleExecutable": "Dummy"]
        try t.file(relative + "/Contents/Info.plist", contents: try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0))
        try t.file(relative + "/Contents/MacOS/Dummy", size: 4096)
        return t.path(relative)
    }

    /// One item per user leftover location, named the way each folder names things.
    static let leftovers = [
        "Library/Application Scripts/\(id)/script.scpt",
        "Library/Application Support/\(id)/data.db",
        "Library/Caches/\(id)/Cache.db",
        "Library/Containers/\(id)/Data/Library/Preferences/x.plist",
        "Library/Group Containers/ABCDE12345.\(id)/shared.db",
        "Library/HTTPStorages/\(id)/httpstorages.sqlite",
        "Library/LaunchAgents/\(id).agent.plist",
        "Library/Logs/\(id)/app.log",
        "Library/Preferences/\(id).plist",
        "Library/Preferences/ByHost/\(id).12345678-ABCD-1234-ABCD-1234567890AB.plist",
        "Library/Saved Application State/\(id).savedState/windows.plist",
        "Library/WebKit/\(id)/WebsiteData/x",
    ]

    /// Must survive any Dummy uninstall.
    static let tripwires = [
        "Library/Application Support/\(id).Pro/data.db",       // a different, installed app
        "Library/Preferences/\(id).Pro.plist",
        "Library/Application Support/com.example.Other/data.db",
        "Library/Caches/com.apple.\(id)/x",                     // Apple's prefix: never
        "Documents/\(id)/mine.txt",                             // not a leftover location
        "Library/Application Support/Shared Suite Data/x",
        "Applications/Other.app/Contents/Info.plist",
    ]

    static func build(_ t: TestHome) throws -> String {
        let path = try app(t, "Applications/TidyTestDummy.app", bundleID: id, name: "TidyTestDummy")
        try app(t, "Applications/TidyTestDummy Pro.app", bundleID: id + ".Pro", name: "TidyTestDummy Pro")
        for p in leftovers { try t.file(p, size: 2048) }
        for p in tripwires { try t.file(p) }
        // A symlink named like the app that leads into Documents: offered never.
        try t.symlink("Library/Caches/\(id).link", to: t.path("Documents"))
        return path
    }

    static func context(_ t: TestHome, rules: RuleSet = rules, fda: Bool = true, running: Set<String> = []) -> CleanupContext {
        CleanupContext(home: t.home, rules: rules, guards: FakeGuards(running: running), hasFullDiskAccess: fda,
                       trash: HomeTrash(home: t.home), unloader: nil, appVersion: "test")
    }

    static func catalog(_ t: TestHome, apple: Set<String> = []) -> AppCatalog {
        AppCatalog(home: t.home, systemApplications: t.path("System Applications"), signatures: FakeSignatures(applePaths: apple),
                   usage: FakeUsage())
    }
}

struct InventoryTests {
    @Test func listsUserAndVendorAppsButNeverAppleOrTidyMyMac() throws {
        let t = try TestHome("inventory")
        defer { t.cleanUp() }
        try Dummy.app(t, "Applications/TidyTestDummy.app", bundleID: Dummy.id)
        try Dummy.app(t, "System Applications/Vendor/Suite.app", bundleID: "com.example.suite")
        try Dummy.app(t, "System Applications/Top.app", bundleID: "com.example.top")
        try Dummy.app(t, "System Applications/Vendor/Deeper/TooDeep.app", bundleID: "com.example.deep")
        try Dummy.app(t, "System Applications/Signed.app", bundleID: "com.example.applesigned")
        try Dummy.app(t, "System Applications/Fake.app", bundleID: "com.apple.fake")
        try Dummy.app(t, "System Applications/TidyMyMac.app", bundleID: "io.github.joswalt.TidyMyMac")
        try t.file("System Applications/Broken.app/Contents/MacOS/x")  // no Info.plist
        let listing = Dummy.catalog(t, apple: ["Signed.app"]).list()
        #expect(listing.apps.map(\.bundleID).sorted() == ["com.example.suite", "com.example.top", Dummy.id])
        #expect(listing.allBundleIDs.contains("com.example.applesigned"))
        let dummy = try #require(listing.apps.first { $0.bundleID == Dummy.id })
        #expect(dummy.location == .user && dummy.allocatedBytes > 0 && dummy.versionText == "1.0 (100)")
    }

    /// Apple-signed apps are never offered, checked against the real signature checker.
    @Test func realAppleAppsAreNeverOffered() throws {
        let t = try TestHome("apple")
        defer { t.cleanUp() }
        let catalog = AppCatalog(home: t.home, systemApplications: "/System/Applications", signatures: SystemAppSignatures(), usage: FakeUsage())
        let listing = catalog.list(measure: false)
        #expect(listing.apps.isEmpty)
        #expect(listing.allBundleIDs.contains { $0.hasPrefix("com.apple.") })
    }

    @Test func unusedAppsSplitByLastUsedDate() {
        let now = Date()
        var old = fakeApp("Old", bundleID: "a"); old.lastUsed = now.addingTimeInterval(-200 * 86_400)
        var recent = fakeApp("Recent", bundleID: "b"); recent.lastUsed = now.addingTimeInterval(-10 * 86_400)
        var older = fakeApp("Older", bundleID: "c"); older.lastUsed = now.addingTimeInterval(-400 * 86_400)
        let never = fakeApp("Never", bundleID: "d")
        let r = UnusedApps.split([old, recent, older, never], days: 90, now: now)
        #expect(r.unused.map(\.name) == ["Older", "Old"])
        #expect(r.noDate.map(\.name) == ["Never"])
        #expect(UnusedApps.split([old, recent, older], days: 365, now: now).unused.map(\.name) == ["Older"])
    }
}

struct UninstallerTests {
    /// Spec 017 §4.4: uninstall must find exactly the dummy's leftovers, and the run must move
    /// exactly those (plus the app) to the Trash, leaving everything else byte-identical.
    @Test func dummyUninstallFindsAndRemovesExactlyItsFiles() throws {
        let t = try TestHome("dummy")
        defer { t.cleanUp() }
        let appPath = try Dummy.build(t)
        let listing = Dummy.catalog(t).list()
        let app = try #require(listing.apps.first { $0.bundleID == Dummy.id })
        let ctx = Dummy.context(t)
        let finder = RelatedFileFinder(context: ctx, installedBundleIDs: listing.allBundleIDs, receipts: FakeReceipts())
        let plan = finder.plan(for: app)

        let expected = Set(Dummy.leftovers.map { rel -> String in
            // Each location's direct child is the item (a folder, or the file itself).
            let comps = rel.split(separator: "/")
            let depth = rel.hasPrefix("Library/Preferences/ByHost/") ? 4 : 3
            return t.path(comps.prefix(depth).joined(separator: "/"))
        })
        #expect(Set(plan.related.map(\.path)) == expected)
        #expect(plan.appItem.path == appPath && plan.appItem.ruleID == RelatedFileFinder.appRuleID)
        #expect(plan.kept.contains { $0.path.hasSuffix("\(Dummy.id).Pro") && $0.reason.contains("belongs to") })
        #expect(plan.kept.contains { $0.path.hasSuffix("\(Dummy.id).link") && $0.reason.contains("symbolic link") })
        #expect(!plan.related.contains { $0.name.hasPrefix("com.apple.") })
        #expect(plan.related.allSatisfy { $0.selectedByDefault })

        let before = Snapshot(of: t.home.path)
        let engine = AppRemovalEngine(context: ctx, signatures: FakeSignatures())
        let run = try engine.run([RemovalBatch(ownerBundleID: Dummy.id, items: plan.allItems)], dryRun: false)
        #expect(run.outcome.skipped.isEmpty && run.outcome.failed.isEmpty)
        #expect(run.outcome.done.count == expected.count + 1)
        #expect(run.outcome.done.first?.path == appPath)  // the app goes first

        // Everything outside the removed items (and the Trash) is unchanged.
        let after = Snapshot(of: t.home.path)
        let removed = Set(([appPath] + expected).map { String($0.dropFirst(t.home.path.count + 1)) })
        let survivors = before.entries.filter { rel, _ in !removed.contains { rel == $0 || rel.hasPrefix($0 + "/") } }
        // Folders that lost a child get a new mtime; their files must be byte-identical.
        for (rel, entry) in survivors {
            if entry.mode & S_IFMT == S_IFDIR { #expect(after.entries[rel] != nil, "\(rel) gone") } else {
                #expect(after.entries[rel] == entry, "\(rel) changed")
            }
        }
        for rel in removed { #expect(after.entries[rel] == nil, "\(rel) still there") }
        // In the Trash, same inodes, and the run log says where.
        for item in run.outcome.done {
            let trashed = try #require(item.trashPath)
            #expect(trashed.hasPrefix(t.home.trash.path))
            #expect(FileStatus.lstat(trashed) != nil)
        }
        #expect(run.record.header.module == "applications" && run.record.summary != nil)
    }

    @Test func dryRunChangesNothing() throws {
        let t = try TestHome("dummy-dry")
        defer { t.cleanUp() }
        try Dummy.build(t)
        let listing = Dummy.catalog(t).list()
        let app = try #require(listing.apps.first { $0.bundleID == Dummy.id })
        let ctx = Dummy.context(t)
        let plan = RelatedFileFinder(context: ctx, installedBundleIDs: listing.allBundleIDs, receipts: nil).plan(for: app)
        let before = Snapshot(of: t.home.path)
        let run = try AppRemovalEngine(context: ctx, signatures: FakeSignatures())
            .run([RemovalBatch(ownerBundleID: Dummy.id, items: plan.allItems)], dryRun: true)
        #expect(run.outcome.done.count == plan.allItems.count)
        #expect(run.record.header.dryRun)
        let after = Snapshot(of: t.home.path)
        func files(_ s: Snapshot) -> [String: Snapshot.Entry] {
            s.entries.filter { $0.value.mode & S_IFMT != S_IFDIR && !$0.key.hasPrefix("Library/Application Support/TidyMyMac") }
        }
        #expect(files(after) == files(before))
        #expect(Set(after.entries.keys).isSuperset(of: before.entries.keys))
    }

    @Test func runningAppIsNotRemovedNorItsFiles() throws {
        let t = try TestHome("dummy-running")
        defer { t.cleanUp() }
        try Dummy.build(t)
        let listing = Dummy.catalog(t).list()
        let app = try #require(listing.apps.first { $0.bundleID == Dummy.id })
        let plan = RelatedFileFinder(context: Dummy.context(t), installedBundleIDs: listing.allBundleIDs, receipts: nil).plan(for: app)
        let running = Dummy.context(t, running: [Dummy.id])
        let run = try AppRemovalEngine(context: running, signatures: FakeSignatures())
            .run([RemovalBatch(ownerBundleID: Dummy.id, items: plan.allItems)], dryRun: false)
        #expect(run.outcome.done.isEmpty)
        #expect(run.outcome.skipped.allSatisfy { $0.reason?.contains("is running") == true })
        #expect(FileStatus.lstat(app.path) != nil)
    }

    @Test func freshChecksBeforeEachItem() throws {
        let t = try TestHome("dummy-fresh")
        defer { t.cleanUp() }
        try Dummy.build(t)
        let listing = Dummy.catalog(t).list()
        let app = try #require(listing.apps.first { $0.bundleID == Dummy.id })
        let ctx = Dummy.context(t)
        let plan = RelatedFileFinder(context: ctx, installedBundleIDs: listing.allBundleIDs, receipts: nil).plan(for: app)
        // Between scan and run: one item is replaced, one becomes a symlink to Documents.
        try t.remove("Library/Caches/\(Dummy.id)")
        try t.file("Library/Caches/\(Dummy.id)/new.db")
        try t.remove("Library/Logs/\(Dummy.id)")
        try t.symlink("Library/Logs/\(Dummy.id)", to: t.path("Documents"))
        let run = try AppRemovalEngine(context: ctx, signatures: FakeSignatures())
            .run([RemovalBatch(ownerBundleID: Dummy.id, items: plan.allItems)], dryRun: false)
        let skipped = Dictionary(uniqueKeysWithValues: run.outcome.skipped.map { ($0.path, $0.reason ?? "") })
        #expect(skipped[t.path("Library/Caches/\(Dummy.id)")] == "the item was replaced since the scan")
        #expect(skipped[t.path("Library/Logs/\(Dummy.id)")] == "the item is a symbolic link")
        #expect(FileStatus.lstat(t.path("Documents/\(Dummy.id)/mine.txt")) != nil)
    }

    /// Root-level files go through the helper only for owners whose app was removed; their
    /// results land in the same run log.
    @Test func rootItemsOnlyForRemovedApps() async throws {
        let t = try TestHome("dummy-root")
        defer { t.cleanUp() }
        try Dummy.build(t)
        let listing = Dummy.catalog(t).list()
        let dummy = try #require(listing.apps.first { $0.bundleID == Dummy.id })
        let pro = try #require(listing.apps.first { $0.bundleID == Dummy.id + ".Pro" })
        let ctx = Dummy.context(t, running: [pro.bundleID])
        let finder = RelatedFileFinder(context: ctx, installedBundleIDs: listing.allBundleIDs, receipts: nil)
        let batches = [dummy, pro].map { RemovalBatch(ownerBundleID: $0.bundleID, items: finder.plan(for: $0).allItems) }
        let run = try await AppRemovalEngine(context: ctx, signatures: FakeSignatures()).run(batches, dryRun: false) { owners in
            #expect(owners == [Dummy.id])
            return [RunItem(ruleID: "leftover.system.libraryLeftovers", path: "helper-item", allocatedBytes: 1, action: .trash, result: .done)]
        }
        #expect(run.record.items.contains { $0.path == "helper-item" })
        #expect(FileStatus.lstat(pro.path) != nil && FileStatus.lstat(dummy.path) == nil)
    }

    @Test func appBundleMustStillBeTheSameApp() throws {
        let t = try TestHome("dummy-swap")
        defer { t.cleanUp() }
        try Dummy.build(t)
        let listing = Dummy.catalog(t).list()
        let app = try #require(listing.apps.first { $0.bundleID == Dummy.id })
        let ctx = Dummy.context(t)
        let plan = RelatedFileFinder(context: ctx, installedBundleIDs: listing.allBundleIDs, receipts: nil).plan(for: app)
        // Apple-signed by the time of the run: refused, and its files stay.
        let run = try AppRemovalEngine(context: ctx, signatures: FakeSignatures(applePaths: ["TidyTestDummy.app"]))
            .run([RemovalBatch(ownerBundleID: Dummy.id, items: plan.allItems)], dryRun: false)
        #expect(run.outcome.done.isEmpty)
        #expect(run.outcome.skipped.first?.reason == "signed by Apple")
        #expect(run.outcome.skipped.dropFirst().allSatisfy { $0.reason?.hasPrefix("the app itself wasn't removed") == true })
    }

    @Test func containersNeedFullDiskAccess() throws {
        let t = try TestHome("dummy-fda")
        defer { t.cleanUp() }
        try Dummy.build(t)
        let listing = Dummy.catalog(t).list()
        let app = try #require(listing.apps.first { $0.bundleID == Dummy.id })
        let plan = RelatedFileFinder(context: Dummy.context(t, fda: false), installedBundleIDs: listing.allBundleIDs, receipts: nil).plan(for: app)
        #expect(Set(plan.needsFullDiskAccess) == ["leftover.user.containers", "leftover.user.group-containers"])
        #expect(!plan.related.contains { $0.path.contains("/Containers/") || $0.path.contains("/Group Containers/") })
    }

    /// A suite app with `sharedWith` keeps the files its partner still uses (spec 017 §4.4).
    @Test func suiteAppKeepsSharedFiles() throws {
        let t = try TestHome("suite")
        defer { t.cleanUp() }
        let word = "io.github.joswalt.TidyTest.SuiteWriter", sheet = "io.github.joswalt.TidyTest.SuiteSheets"
        try Dummy.app(t, "Applications/Writer.app", bundleID: word)
        try Dummy.app(t, "Applications/Sheets.app", bundleID: sheet)
        try t.file("Library/Application Support/\(word)/own.db")
        try t.file("Library/Application Support/\(sheet)/own.db")
        try t.file("Library/Group Containers/ABCDE12345.TidyTestSuiteShared/shared.db")
        try t.file("Library/Caches/TidyTestSuiteShared.cache/x")
        var rules = Dummy.rules
        rules.appOverrides = [
            try JSONDecoder().decode(AppOverride.self, from: Data("""
            {"bundleId": "\(word)", "extraTerms": ["TidyTestSuiteShared"], "sharedWith": ["\(sheet)"]}
            """.utf8)),
            try JSONDecoder().decode(AppOverride.self, from: Data("""
            {"bundleId": "\(sheet)", "extraTerms": ["TidyTestSuiteShared"]}
            """.utf8)),
        ]
        let listing = Dummy.catalog(t).list()
        let writer = try #require(listing.apps.first { $0.bundleID == word })
        let ctx = Dummy.context(t, rules: rules)
        let plan = RelatedFileFinder(context: ctx, installedBundleIDs: listing.allBundleIDs, receipts: nil).plan(for: writer)
        #expect(plan.related.map(\.name) == [word])
        #expect(plan.kept.filter { $0.reason == "also used by \(sheet)" }.count == 2)

        // With the partner gone, the shared files go with the last app.
        let alone = RelatedFileFinder(context: ctx, installedBundleIDs: [word], receipts: nil).plan(for: writer)
        #expect(Set(alone.related.map(\.name)) == [word, "ABCDE12345.TidyTestSuiteShared", "TidyTestSuiteShared.cache"])
    }

    @Test func overridePathsAndExcludes() throws {
        let t = try TestHome("override")
        defer { t.cleanUp() }
        try Dummy.build(t)
        try t.file("Library/Application Support/Odd Vendor Folder/data")
        try t.file("Documents/OddDummyStuff/keep")
        var rules = Dummy.rules
        rules.appOverrides = [try JSONDecoder().decode(AppOverride.self, from: Data("""
        {"bundleId": "\(Dummy.id)", "extraPaths": ["\(ruleRoot("Library/Application Support/Odd Vendor Folder"))", "\(ruleRoot("Library/Missing"))"],
         "excludeTerms": ["httpstorages"], "excludePaths": ["\(ruleRoot("Library/Logs/" + Dummy.id))"]}
        """.utf8))]
        let listing = Dummy.catalog(t).list()
        let app = try #require(listing.apps.first { $0.bundleID == Dummy.id })
        let plan = RelatedFileFinder(context: Dummy.context(t, rules: rules), installedBundleIDs: listing.allBundleIDs, receipts: nil).plan(for: app)
        #expect(plan.related.contains { $0.path == t.path("Library/Application Support/Odd Vendor Folder") })
        #expect(!plan.related.contains { $0.path.hasSuffix("/Logs/\(Dummy.id)") })
        #expect(plan.kept.contains { $0.path.hasSuffix("/Logs/\(Dummy.id)") && $0.reason == "excluded for this app" })
    }

    @Test func receiptsAndRootItemsThroughTheHelper() throws {
        let t = try TestHome("receipts")
        defer { t.cleanUp() }
        try Dummy.build(t)
        let receipts = FakeReceipts(owning: ["TidyTestDummy.app": ["io.github.joswalt.pkg.dummy"]],
                                    all: ["io.github.joswalt.pkg.dummy", "com.apple.pkg.Core", "\(Dummy.id).helper.pkg", "com.example.other"],
                                    filesOf: ["io.github.joswalt.pkg.dummy": ["\(Sys.appSupport)/Dummy Vendor/engine/x.bin",
                                                                              "\(Sys.helperTools)/dummyd"]])
        let listing = Dummy.catalog(t).list()
        let app = try #require(listing.apps.first { $0.bundleID == Dummy.id })
        let finder = RelatedFileFinder(context: Dummy.context(t), installedBundleIDs: listing.allBundleIDs, receipts: receipts)
        let plan = finder.plan(for: app)
        #expect(plan.receipts == ["\(Dummy.id).helper.pkg", "io.github.joswalt.pkg.dummy"])

        // What a helper scan of libraryLeftovers and launchItems reported (paths are display only).
        func item(_ zone: HelperZone, _ path: String, programExists: Bool? = nil) -> HelperFoundItem {
            HelperFoundItem(handle: UUID(), zone: zone, path: path, allocatedBytes: 10, modified: Date(), isDirectory: true,
                            launchProgramExists: programExists)
        }
        let found = [
            item(.libraryLeftovers, "\(Sys.appSupport)/Dummy Vendor"),       // via receipt
            item(.libraryLeftovers, "\(Sys.helperTools)/dummyd"),           // via receipt
            item(.libraryLeftovers, "\(Sys.caches)/\(Dummy.id)"),                     // via name
            item(.launchItems, "\(Sys.daemons)/\(Dummy.id).helper.plist", programExists: true),
            item(.libraryLeftovers, "\(Sys.appSupport)/\(Dummy.id).Pro"),    // another app
            item(.libraryLeftovers, "\(Sys.appSupport)/Unrelated"),
            item(.systemCaches, "\(Sys.caches)/\(Dummy.id)"),                         // wrong zone
        ]
        let root = finder.rootRelated(for: plan, items: found)
        #expect(Set(root.offered.map(\.path)) == ["\(Sys.appSupport)/Dummy Vendor", "\(Sys.helperTools)/dummyd",
                                                  "\(Sys.caches)/\(Dummy.id)", "\(Sys.daemons)/\(Dummy.id).helper.plist"])
        #expect(root.offered.allSatisfy { $0.viaHelper && $0.action == .trash })
        #expect(root.kept.map(\.path) == ["\(Sys.appSupport)/\(Dummy.id).Pro"])
    }
}

struct LeftoverTests {
    @Test func ownerBundleIDFromLibraryNames() {
        #expect(LeftoverScanner.ownerBundleID(fromName: "com.example.App") == "com.example.App")
        #expect(LeftoverScanner.ownerBundleID(fromName: "com.example.App.plist") == "com.example.App")
        #expect(LeftoverScanner.ownerBundleID(fromName: "com.example.App.savedState") == "com.example.App")
        #expect(LeftoverScanner.ownerBundleID(fromName: "com.example.App.12345678-ABCD-1234-ABCD-1234567890AB.plist") == "com.example.App")
        #expect(LeftoverScanner.ownerBundleID(fromName: "ABCDE12345.com.example.App") == "com.example.App")
        #expect(LeftoverScanner.ownerBundleID(fromName: "group.com.example.App") == "com.example.App")
        #expect(LeftoverScanner.ownerBundleID(fromName: "Google") == nil)
        #expect(LeftoverScanner.ownerBundleID(fromName: "com.example") == nil)
        #expect(LeftoverScanner.ownerBundleID(fromName: "ABCDE12345.Office") == nil)
        #expect(LeftoverScanner.ownerBundleID(fromName: "1.2.3") == nil)
        #expect(LeftoverScanner.ownerBundleID(fromName: "My Folder.with.dots") == nil)
    }

    @Test func groupsLeftoversOfMissingAppsOnly() throws {
        let t = try TestHome("leftovers")
        defer { t.cleanUp() }
        try Dummy.app(t, "Applications/Kept.app", bundleID: "com.example.kept")
        // Gone app: leftovers in several places.
        try t.file("Library/Application Support/com.example.gone/data.db", size: 4096)
        try t.file("Library/Preferences/com.example.gone.plist")
        try t.file("Library/Caches/com.example.gone/c")
        try SnapshotDiffTestsShim.launchAgent(t, "Library/LaunchAgents/com.example.gone.agent.plist", program: t.path("Applications/Gone.app/x"))
        // Not leftovers: installed app, its helper, running agent, Apple, ours, Launch Services-known, working agent.
        try t.file("Library/Preferences/com.example.kept.plist")
        try t.file("Library/Caches/com.example.kept.helper/c")
        try t.file("Library/Preferences/com.example.daemon.plist")
        try t.file("Library/Preferences/com.apple.finder.plist")
        try t.file("Library/Preferences/io.github.joswalt.TidyMyMac.plist")
        try t.file("Library/Preferences/com.example.registered.plist")
        try t.file("bin/tool")
        try SnapshotDiffTestsShim.launchAgent(t, "Library/LaunchAgents/com.example.working.plist", program: t.path("bin/tool"))
        // Same vendor as an installed app: listed, flagged.
        try t.file("Library/Application Support/com.example.oldtool/x")
        try t.file("Library/Application Support/Google/x")  // not a bundle ID: not offered

        let ctx = CleanupContext(home: t.home, rules: Dummy.rules,
                                 guards: FakeGuards(running: ["com.example.daemon"], installed: ["com.example.registered"]),
                                 hasFullDiskAccess: true, trash: HomeTrash(home: t.home), unloader: nil, appVersion: "test")
        let listing = Dummy.catalog(t).list()
        let result = LeftoverScanner(context: ctx, installedBundleIDs: listing.allBundleIDs).scan()
        let owners = result.groups.map(\.ownerBundleID)
        // The agent `com.example.gone.agent` joins its app's group.
        #expect(Set(owners) == ["com.example.gone", "com.example.oldtool"])
        let gone = try #require(result.groups.first { $0.ownerBundleID == "com.example.gone" })
        #expect(gone.items.count == 4)
        #expect(gone.items.allSatisfy { $0.risk == .caution && !$0.selectedByDefault })
        // Every group here shares the vendor "com.example" with the installed Kept app.
        #expect(result.groups.allSatisfy { $0.vendorHasInstalledApp })

        // Removal: unticked by default, so only what is picked goes, to the Trash, logged.
        let pick = gone.items.filter { $0.path.hasSuffix("Application Support/com.example.gone") }
        let run = try AppRemovalEngine(context: ctx, signatures: FakeSignatures())
            .run([RemovalBatch(ownerBundleID: gone.ownerBundleID, items: pick)], dryRun: false)
        #expect(run.outcome.done.map(\.path) == pick.map(\.path))
        #expect(FileStatus.lstat(t.path("Library/Preferences/com.example.gone.plist")) != nil)
    }

    @Test func rootLeftoversFromHelperScan() throws {
        let t = try TestHome("root-leftovers")
        defer { t.cleanUp() }
        let ctx = Dummy.context(t)
        let scanner = LeftoverScanner(context: ctx, installedBundleIDs: ["com.example.kept"])
        let items = [
            HelperFoundItem(handle: UUID(), zone: .libraryLeftovers, path: "\(Sys.appSupport)/com.example.gone", allocatedBytes: 5,
                            modified: Date(), isDirectory: true, launchProgramExists: nil),
            HelperFoundItem(handle: UUID(), zone: .launchItems, path: "\(Sys.daemons)/com.example.gone.helper.plist", allocatedBytes: 1,
                            modified: Date(), isDirectory: false, launchProgramExists: false),
            HelperFoundItem(handle: UUID(), zone: .launchItems, path: "\(Sys.daemons)/com.example.alive.plist", allocatedBytes: 1,
                            modified: Date(), isDirectory: false, launchProgramExists: true),
            HelperFoundItem(handle: UUID(), zone: .libraryLeftovers, path: "\(Sys.prefs)/com.example.kept.plist", allocatedBytes: 1,
                            modified: Date(), isDirectory: false, launchProgramExists: nil),
        ]
        let groups = scanner.rootGroups(items: items)
        #expect(groups.map(\.ownerBundleID) == ["com.example.gone"])
        #expect(groups.first?.items.count == 2 && groups.first?.items.allSatisfy { $0.viaHelper } == true)
    }
}

enum SnapshotDiffTestsShim {
    static func launchAgent(_ t: TestHome, _ path: String, program: String) throws {
        let dict: [String: Any] = ["Label": (path as NSString).lastPathComponent, "ProgramArguments": [program]]
        try t.file(path, contents: try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0))
    }
}

/// System folders taken from the helper's zone table, so tests hold no literal system paths.
/// These strings only label fake helper results; nothing here touches them.
enum Sys {
    static let appSupport = HelperZone.libraryLeftovers.roots[0]
    static let prefs = HelperZone.libraryLeftovers.roots[1]
    static let helperTools = HelperZone.libraryLeftovers.roots[2]
    static let caches = HelperZone.libraryLeftovers.roots[3]
    static let daemons = HelperZone.launchItems.roots[1]
}
