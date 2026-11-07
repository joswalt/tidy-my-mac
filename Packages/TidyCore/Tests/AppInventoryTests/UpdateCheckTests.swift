import Foundation
import SafetyFloor
import Testing
import TestSupport
@testable import AppInventory

/// Spec 017 §4.4: fixture appcasts (Sparkle, Electron, malformed, http://, deltas, min-system
/// filters) and Sparkle's comparator tests. No network: feeds come from Fixtures/.
enum Fixture {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    static func data(_ name: String) throws -> Data { try Data(contentsOf: folder.appendingPathComponent(name)) }
    static func text(_ name: String) throws -> String { String(decoding: try data(name), as: UTF8.self) }
}

/// Serves fixture files by URL; any other URL fails like a network error. Records what was asked.
final class FixtureFetcher: FeedFetcher, @unchecked Sendable {
    let routes: [String: String]
    private let lock = NSLock()
    private(set) var requested: [String] = []

    init(_ routes: [String: String]) { self.routes = routes }

    func fetch(_ url: URL) async throws -> Data {
        lock.withLock { requested.append(url.absoluteString) }
        guard url.scheme == "https" else { throw FetchError("insecure feed") }
        guard let file = routes[url.absoluteString] else { throw FetchError("offline in tests") }
        return try Fixture.data(file)
    }
}

func fakeApp(_ name: String = "TidyTestDummy", bundleID: String = "io.github.joswalt.TidyTest.Dummy", short: String? = "1.0",
             build: String? = "100", sparkle: String? = nil, electron: String? = nil, appStore: Bool = false) -> InstalledApp {
    InstalledApp(path: "/Fixture/\(name).app", location: .user, name: name, bundleID: bundleID, shortVersion: short, buildVersion: build,
                 identity: ItemIdentity(device: 1, inode: 1), ownerUID: 501, teamID: nil, sparkleFeed: sparkle, electronFeed: electron,
                 isFromAppStore: appStore)
}

struct VersionComparatorTests {
    // Ported verbatim from Sparkle's Tests/SUVersionComparisonTest.m (2.x @ 14fdbf2, MIT).
    func ascending(_ a: String, _ b: String) { #expect(VersionComparator.compare(a, b) == .orderedAscending, "\(a) < \(b)") }
    func descending(_ a: String, _ b: String) { #expect(VersionComparator.compare(a, b) == .orderedDescending, "\(a) > \(b)") }
    func equal(_ a: String, _ b: String) { #expect(VersionComparator.compare(a, b) == .orderedSame, "\(a) == \(b)") }

    @Test func numbers() {
        ascending("1.0", "1.1")
        equal("1.0", "1.0")
        descending("2.0", "1.1")
        descending("0.1", "0.0.1")
        // descending(".1", "0.0.1")  Known bug in Sparkle, kept as is (see knownBug below).
        ascending("0.1", "0.1.2")
        equal("1.0", "1.0.0")
        equal("1.0.0", "1.0")
    }

    @Test func commitSHAs() {
        ascending("1.5.5-335d3e2", "1.5.6-b252311")
        equal("1.5.5-335d3e2", "1.5.5-a655360")
        descending("1.5.6-b252311", "1.5.5-335d3e2")
        equal("1.5-335d3e2", "1.5.0-335d3e2")
        equal("1.5.0-335d3e2", "1.5-335d3e2")
    }

    @Test func prereleases() {
        ascending("1.5.5", "1.5.6a1")
        ascending("1.1.0b1", "1.1.0b2")
        ascending("1.1.1b2", "1.1.2b1")
        ascending("1.1.1b2", "1.1.2a1")
        ascending("1.0a1", "1.0b1")
        ascending("1.0b1", "1.0")
        ascending("0.9", "1.0a1")
        ascending("1.0b", "1.0b2")
        ascending("1.0b10", "1.0b11")
        ascending("1.0b9", "1.0b10")
        ascending("1.0rc", "1.0")
        ascending("1.0b", "1.0")
        ascending("1.0pre1", "1.0")
        equal("1.0pre1", "1.0.0pre1")
        equal("1.0.0pre1", "1.0pre1")
    }

    @Test func versionsWithBuildNumbers() {
        ascending("1.0 (1234)", "1.0 (1235)")
        ascending("1.0b1 (1234)", "1.0 (1234)")
        ascending("1.0b5 (1234)", "1.0b5 (1235)")
        ascending("1.0b5 (1234)", "1.0.1b5 (1234)")
        ascending("1.0.1b5 (1234)", "1.0.1b6 (1234)")
        ascending("2.0.0.2429", "2.0.0.2430")
        ascending("1.1.1.1818", "2.0.0.2430")
        ascending("3.3 (5847)", "3.3.1b1 (5902)")
        equal("3.3 (5847)", "3.3.0 (5847)")
        equal("3.3.0 (5847)", "3.3 (5847)")
        equal("1.1.1.1818", "1.1.1.1818.0")
        equal("1.1.1.1818.0", "1.1.1.1818")
        equal("3.3b1 (5902)", "3.3.0b1 (5902)")
        equal("3.3.0b1 (5902)", "3.3b1 (5902)")
    }

    @Test func versionsWithReverseDateBasedNumbers() {
        ascending("201210251627", "201211051041")
        equal("201210251627.0", "201210251627")
        equal("201210251627", "201210251627.0")
    }

    /// Sparkle's known `.1` bug is ported as is (research 013 §3): `.1` sorts below `0.0.1`.
    @Test func knownBug() {
        ascending(".1", "0.0.1")
    }
}

struct AppcastTests {
    @Test func picksHighestVersionNotFeedOrderAndKeepsFirstOfTies() throws {
        let items = try Appcast.parse(Fixture.data("sparkle-basic.xml"))
        #expect(items.count == 4)
        #expect(items[0].version == "110" && items[0].shortVersion == "1.1")
        // Element form is the fallback when the enclosure has no attribute.
        #expect(items[1].version == "130" && items[1].releaseNotesLink == "https://example.com/notes/1.3.html")
        let best = try #require(Appcast.bestItem(items, installedBuild: "100", osVersion: "26.7.1"))
        #expect(best.shortVersion == "1.3")
        #expect(best.title == "Version 1.3")
    }

    @Test func matchesNamespaceURINotPrefix() throws {
        let custom = try Appcast.parse(Fixture.data("sparkle-custom-prefix.xml"))
        #expect(custom.map(\.version) == ["200", "210"])
        #expect(Appcast.bestItem(custom, installedBuild: "1", osVersion: "26.0")?.shortVersion == "2.1")
        let wrong = try Appcast.parse(Fixture.data("sparkle-wrong-namespace.xml"))
        #expect(wrong.first?.version == nil)
        #expect(Appcast.bestItem(wrong, installedBuild: "1", osVersion: "26.0") == nil)
    }

    @Test func deltasNeverWin() throws {
        let items = try Appcast.parse(Fixture.data("sparkle-deltas.xml"))
        #expect(items.count == 2)
        #expect(items[0].version == "300" && !items[0].isDelta)
        #expect(items[1].isDelta)
        #expect(Appcast.bestItem(items, installedBuild: "290", osVersion: "26.0")?.version == "300")
    }

    @Test func sparkleFilters() throws {
        let items = try Appcast.parse(Fixture.data("sparkle-filters.xml"))
        #expect(items.count == 6)
        // From 1.0 (100): 1.6.5 needs 160 first, 2.0 needs macOS 30, 1.9 is for ≤ 13.9, 1.8b is beta,
        // 1.7 is Windows; so 1.5.
        #expect(Appcast.bestItem(items, installedBuild: "100", osVersion: "26.7.1")?.shortVersion == "1.5")
        // From 1.6 (160) the minimumUpdateVersion passes.
        #expect(Appcast.bestItem(items, installedBuild: "160", osVersion: "26.7.1")?.shortVersion == "1.6.5")
        // On macOS 13 the 1.9 item applies, the min-14 item doesn't.
        #expect(Appcast.bestItem(items, installedBuild: "100", osVersion: "13.6")?.shortVersion == "1.9")
    }

    @Test func toleratesTrailingSignatureBlock() throws {
        let items = try Appcast.parse(Fixture.data("sparkle-signed.xml"))
        #expect(items.first?.version == "5.1")
    }

    @Test func malformedFeedIsAnError() {
        #expect(throws: Appcast.ParseError.self) { try Appcast.parse(Fixture.data("malformed.xml")) }
        #expect(throws: Appcast.ParseError.self) { try Appcast.parse(Data("{\"not\": \"xml\"}".utf8)) }
    }
}

struct ElectronFeedTests {
    @Test func feedURLFromAppUpdateYAML() throws {
        #expect(ElectronFeed.latestMacURL(appUpdateYAML: try Fixture.text("app-update-generic.yml"))
                == "https://downloads.example.com/dummy/latest-mac.yml")
        #expect(ElectronFeed.latestMacURL(appUpdateYAML: try Fixture.text("app-update-s3.yml"))
                == "https://dummy-releases.s3.eu-west-1.amazonaws.com/mac/latest-mac.yml")
        #expect(ElectronFeed.latestMacURL(appUpdateYAML: try Fixture.text("app-update-github.yml")) == nil)
    }

    @Test func topLevelVersionOnly() throws {
        #expect(ElectronFeed.version(latestMacYAML: try Fixture.text("latest-mac.yml")) == "4.2.1")
    }
}

struct HomebrewTests {
    @Test func slimCatalogueMatchesByBundleIDThenName() throws {
        let catalog = try CaskCatalog.parse(fullCatalogue: Fixture.data("cask.json"))
        #expect(catalog.entries.count == 5)  // the font-only cask has no app
        #expect(catalog.entry(bundleID: "io.github.joswalt.TidyTest.Dummy", appFileName: "Other.app")?.token == "tidy-dummy")
        #expect(catalog.entry(bundleID: "com.example.unknown", appFileName: "Named.app")?.token == "by-name")
        #expect(catalog.entry(bundleID: "com.example.multi.helper", appFileName: "x.app")?.token == "multi-quit")
        #expect(catalog.entry(bundleID: "com.example.unknown", appFileName: "Nope.app") == nil)
        #expect(catalog.entry(bundleID: "x", appFileName: "Latest.app")?.versions == nil)
        let v = try #require(catalog.entries.first?.versions)
        #expect(v.short == "2.0.0" && v.build == "2000")
    }

    @Test func cacheRoundTripAndWeeklyRefresh() async throws {
        let t = try TestHome("casks")
        defer { t.cleanUp() }
        let cache = UpdateCache(home: t.home)
        let fetcher = FixtureFetcher([CaskCatalog.url: "cask.json"])
        let now = Date()
        let first = await cache.casks(fetcher: fetcher, now: now)
        #expect(first?.entries.count == 5)
        _ = await cache.casks(fetcher: fetcher, now: now.addingTimeInterval(86_400))
        #expect(fetcher.requested.count == 1)  // cached for a week
        _ = await cache.casks(fetcher: fetcher, now: now.addingTimeInterval(8 * 86_400))
        #expect(fetcher.requested.count == 2)
        // A failed refresh keeps the stale copy.
        let offline = FixtureFetcher([:])
        #expect(await cache.casks(fetcher: offline, now: now.addingTimeInterval(30 * 86_400))?.entries.count == 5)
    }
}

struct UpdateCheckerTests {
    let feeds = FixtureFetcher([
        "https://feeds.example.com/dummy.xml": "sparkle-basic.xml",
        "https://feeds.example.com/filters.xml": "sparkle-filters.xml",
        "https://downloads.example.com/dummy/latest-mac.yml": "latest-mac.yml",
        "https://feeds.example.com/broken.xml": "malformed.xml",
    ])

    func checker() -> UpdateChecker { UpdateChecker(fetcher: feeds, osVersion: "26.7.1") }

    @Test func sparkleUpdateComparesBuildAndShowsShortVersion() async {
        let s = await checker().check(fakeApp(sparkle: "\"https://feeds.example.com/dummy.xml\""), casks: nil)
        // The quotes are trimmed when the bundle is read; a raw value with quotes isn't a URL.
        #expect(s.state == .notChecked("The feed address isn't valid"))
        let ok = await checker().check(fakeApp(sparkle: AppBundleReader.trimFeed(" 'https://feeds.example.com/dummy.xml' ")), casks: nil)
        #expect(ok.state == .updateAvailable)
        #expect(ok.installedVersion == "1.0" && ok.availableVersion == "1.3")
        #expect(ok.releaseNotes == "https://example.com/notes/1.3.html")
        let current = await checker().check(fakeApp(short: "1.3", build: "130", sparkle: "https://feeds.example.com/dummy.xml"), casks: nil)
        #expect(current.state == .upToDate)
    }

    @Test func insecureFeedIsNeverFetched() async {
        let s = await checker().check(fakeApp(sparkle: "http://feeds.example.com/dummy.xml"), casks: nil)
        #expect(s.state == .notChecked("Insecure feed, not checked"))
        #expect(!feeds.requested.contains { $0.hasPrefix("http:") })
    }

    @Test func malformedAndUnreachableFeedsAreNotChecked() async {
        let broken = await checker().check(fakeApp(sparkle: "https://feeds.example.com/broken.xml"), casks: nil)
        #expect(broken.state == .notChecked("The feed couldn't be read"))
        let gone = await checker().check(fakeApp(sparkle: "https://feeds.example.com/missing.xml"), casks: nil)
        if case .notChecked(let why) = gone.state { #expect(why.hasPrefix("Couldn't reach the feed")) } else { Issue.record("expected not checked") }
    }

    @Test func electronComparesShortVersion() async {
        let s = await checker().check(fakeApp(short: "4.2.0", build: "999", electron: "https://downloads.example.com/dummy/latest-mac.yml"), casks: nil)
        #expect(s.state == .updateAvailable && s.availableVersion == "4.2.1" && s.source.badge == "Electron")
        let same = await checker().check(fakeApp(short: "4.2.1", electron: "https://downloads.example.com/dummy/latest-mac.yml"), casks: nil)
        #expect(same.state == .upToDate)
    }

    @Test func discoveryOrderAndHomebrewFallback() async throws {
        let casks = try CaskCatalog.parse(fullCatalogue: Fixture.data("cask.json"))
        // App Store wins over everything.
        let mas = await checker().check(fakeApp(sparkle: "https://feeds.example.com/dummy.xml", appStore: true), casks: casks)
        #expect(mas.state == .appStore && mas.source == .appStore)
        // Homebrew `short,build`: build compared with CFBundleVersion.
        let brew = await checker().check(fakeApp(short: "2.0.0", build: "1999"), casks: casks)
        #expect(brew.source == .homebrew(token: "tidy-dummy") && brew.state == .updateAvailable && brew.availableVersion == "2.0.0")
        let brewSame = await checker().check(fakeApp(short: "2.0.0", build: "2000"), casks: casks)
        #expect(brewSame.state == .upToDate)
        // By app file name, short version only.
        let named = await checker().check(fakeApp("Named", bundleID: "com.example.unknown", short: "3.0", build: "3"), casks: casks)
        #expect(named.state == .updateAvailable && named.availableVersion == "3.1")
        // `latest` casks and unknown apps: no update source, shown honestly.
        let latest = await checker().check(fakeApp("Latest", bundleID: "com.example.latest"), casks: casks)
        #expect(latest.state == .notChecked("No update source"))
        #expect(UpdateSource.find(for: fakeApp("Nope", bundleID: "com.example.nope"), casks: casks) == .none)
    }

    @Test func overridesSkipApps() async {
        let c = UpdateChecker(fetcher: feeds, osVersion: "26.7.1", ignoredBundleIDs: ["io.github.joswalt.TidyTest.Dummy"])
        let s = await c.check(fakeApp(sparkle: "https://feeds.example.com/dummy.xml"), casks: nil)
        #expect(s.state == .notChecked("Ignored for this app"))
    }

    @Test func checksManyAppsKeepingOrder() async {
        let apps = (0..<10).map { fakeApp("App\($0)", bundleID: "com.example.app\($0)", sparkle: "https://feeds.example.com/dummy.xml") }
        let results = await checker().check(apps, casks: nil)
        #expect(results.map(\.name) == apps.map(\.name))
        #expect(results.allSatisfy { $0.state == .updateAvailable })
    }

    @Test func resultsCacheRoundTrip() async throws {
        let t = try TestHome("updates")
        defer { t.cleanUp() }
        let cache = UpdateCache(home: t.home)
        let s = await checker().check(fakeApp(sparkle: "https://feeds.example.com/dummy.xml"), casks: nil)
        try cache.save(UpdateCache.Stored(checked: Date(timeIntervalSince1970: 1_000), statuses: [s]))
        let back = try #require(cache.loadUpdates())
        #expect(back.statuses == [s])
        #expect(back.checked == Date(timeIntervalSince1970: 1_000))
    }
}

struct MacOSUpdatesTests {
    @Test func parsesSoftwareUpdateList() {
        let out = """
        Software Update Tool

        Finding available software
        Software Update found the following new or updated software:
        * Label: macOS Tahoe 26.8-25H100
        \tTitle: macOS Tahoe 26.8, Version: 26.8, Size: 3456789KiB, Recommended: YES, Action: restart,
        * Label: Safari26.2TahoeAuto-26.2
        \tTitle: Safari, Version: 26.2, Size: 123456KiB, Recommended: YES,
        """
        let list = MacOSUpdates.parseList(out)
        #expect(list.map(\.label) == ["macOS Tahoe 26.8-25H100", "Safari26.2TahoeAuto-26.2"])
        #expect(list.map(\.title) == ["macOS Tahoe 26.8", "Safari 26.2"])
        #expect(MacOSUpdates.parseList("Software Update Tool\n\nFinding available software\nNo new software available.\n").isEmpty)
    }

    @Test func readsSoftwareUpdatePlistOrSaysUnknown() throws {
        let t = try TestHome("su")
        defer { t.cleanUp() }
        let none = try PropertyListSerialization.data(fromPropertyList: ["LastRecommendedUpdatesAvailable": 0, "RecommendedUpdates": []] as [String: Any],
                                                      format: .xml, options: 0)
        try t.file("su-none.plist", contents: none)
        #expect(MacOSUpdates.readPlist(at: t.path("su-none.plist")) == .updates([]))
        let some = try PropertyListSerialization.data(fromPropertyList: ["RecommendedUpdates": [
            ["Identifier": "macOS Tahoe 26.8-25H100", "Display Name": "macOS Tahoe", "Display Version": "26.8"]]] as [String: Any],
                                                      format: .xml, options: 0)
        try t.file("su-some.plist", contents: some)
        #expect(MacOSUpdates.readPlist(at: t.path("su-some.plist")) == .updates([.init(label: "macOS Tahoe 26.8-25H100", title: "macOS Tahoe 26.8")]))
        try t.file("bad.plist", contents: Data("nope".utf8))
        #expect(MacOSUpdates.readPlist(at: t.path("bad.plist")) == .unknown)
        #expect(MacOSUpdates.readPlist(at: t.path("missing.plist")) == .unknown)
    }

    @Test func listTimesOut() async {
        // /bin/sleep stands in for a hung softwareupdate: the timeout must stop it.
        await #expect(throws: MacOSUpdates.ListError.timedOut(0.3)) {
            _ = try await MacOSUpdates.list(timeout: 0.3, tool: "/bin/sleep", arguments: ["5"])
        }
    }
}
