import Foundation
import Testing
import TestSupport
@testable import DiskAnalysis
import SafetyFloor

/// Spec 014's rules (017 §4.3 DiskAnalysis): matching, clones, hard links, scope, auto-select, cache.
struct DuplicateFinderTests {
    static let mb = 1_048_576

    /// Deterministic content of `size` bytes, varied by `seed`.
    static func data(_ size: Int, seed: UInt8 = 1) -> Data {
        Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ Int(seed)) })
    }

    func scan(_ t: TestHome, cache: HashCache? = nil, extra: [String] = []) -> [DuplicateGroup] {
        let scope = ClutterScope(folders: ClutterScope.defaultFolders(t.home) + extra)
        let files = ClutterWalker(home: t.home).files(scope, includePackages: false)
        return DuplicateFinder(cache: cache).groups(files)
    }

    func setCreated(_ t: TestHome, _ rel: String, daysAgo: Double) throws {
        try FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(-daysAgo * 86_400)], ofItemAtPath: t.path(rel))
    }

    @Test func onlyFullHashMatchesAreDuplicates() throws {
        let t = try TestHome("dup-match")
        defer { t.cleanUp() }
        let a = Self.data(2 * Self.mb)
        try t.file("Documents/report.pdf", contents: a)
        try t.file("Downloads/report copy.pdf", contents: a)
        // Same size, same first and last 16 KB, different middle: not a duplicate.
        var middle = a
        middle[Self.mb] ^= 0xFF
        try t.file("Pictures/almost.pdf", contents: middle)
        // Same size, different start: not a duplicate.
        try t.file("Music/other.pdf", contents: Self.data(2 * Self.mb, seed: 9))
        // Same name pattern but different content: never matched by name.
        try t.file("Downloads/report (1).pdf", contents: Self.data(2 * Self.mb, seed: 3))

        let groups = scan(t)
        #expect(groups.count == 1)
        #expect(Set(groups[0].files.map(\.entry.name)) == ["report.pdf", "report copy.pdf"])
        #expect(groups[0].size == Int64(2 * Self.mb))
    }

    @Test func scopeAndSkips() throws {
        let t = try TestHome("dup-scope")
        defer { t.cleanUp() }
        let a = Self.data(Self.mb + 10)
        try t.file("Documents/a.bin", contents: a)
        try t.file("Library/Application Support/X/a.bin", contents: a)     // ~/Library never
        try t.file("Library/Mobile Documents/com~apple~CloudDocs/a.bin", contents: a)  // iCloud Drive never
        try t.file("Documents/.hidden.bin", contents: a)                   // hidden never
        try t.file("Documents/proj/.git/objects/a.bin", contents: a)       // .git never
        try t.file("Documents/Thing.app/Contents/a.bin", contents: a)      // inside a package never
        try t.file("Projects/a.bin", contents: a)                          // outside the default scope
        let small = Self.data(Self.mb - 1)
        try t.file("Documents/small1", contents: small)                    // under 1 MB
        try t.file("Desktop/small2", contents: small)
        try t.symlink("Desktop/link.bin", to: t.path("Documents/a.bin"))   // links never followed
        #expect(scan(t).isEmpty)

        // Add Folder… brings in another folder.
        let added = scan(t, extra: [t.path("Projects")])
        #expect(added.count == 1)
        #expect(Set(added[0].files.map(\.entry.name)) == ["a.bin"])
        #expect(added[0].files.count == 2)
    }

    @Test func hardLinksAreOneFile() throws {
        let t = try TestHome("dup-hardlink")
        defer { t.cleanUp() }
        try t.file("Documents/a.bin", contents: Self.data(Self.mb + 1))
        try t.hardLink("Desktop/a-link.bin", to: "Documents/a.bin")
        #expect(scan(t).isEmpty, "a hard link is the same file, never a duplicate")
    }

    @Test func clonesAreFlaggedUntickedAndFreeNothing() throws {
        let t = try TestHome("dup-clone")
        defer { t.cleanUp() }
        let a = Self.data(2 * Self.mb)
        try t.file("Documents/orig.mov", contents: a)
        try t.clone("Desktop/orig clone.mov", of: "Documents/orig.mov")
        try t.file("Downloads/copy.mov", contents: a)
        let groups = scan(t)
        #expect(groups.count == 1)
        let g = groups[0]
        #expect(g.files.count == 3)
        let clone = try #require(g.files.first { $0.entry.name == "orig clone.mov" })
        let copy = try #require(g.files.first { $0.entry.name == "copy.mov" })
        #expect(g.sharesSpace(clone))
        #expect(!g.sharesSpace(copy))

        let sel = DuplicateSelection.automatic(groups, rule: .oldest, home: t.home)
        #expect(!sel.contains(clone), "clones start unticked")
        #expect(sel.contains(copy))
        #expect(sel.freedBytes(groups) == copy.entry.allocatedBytes)
        // Ticking the clone by hand still frees nothing while the original stays.
        var more = sel
        more.set(clone, in: g, true)
        #expect(more.freedBytes(groups) == copy.entry.allocatedBytes)
        #expect(g.reclaimableBytes == copy.entry.allocatedBytes)
    }

    @Test func autoSelectKeepsTheCopyOutsideDownloadsAndDesktop() throws {
        let t = try TestHome("dup-keep")
        defer { t.cleanUp() }
        let a = Self.data(Self.mb + 100)
        try t.file("Downloads/x.zip", contents: a)
        try t.file("Desktop/x.zip", contents: a)
        try t.file("Documents/Archive/x.zip", contents: a)
        try t.file("Pictures/x.zip", contents: a)
        try setCreated(t, "Downloads/x.zip", daysAgo: 900)        // oldest, but in Downloads
        try setCreated(t, "Documents/Archive/x.zip", daysAgo: 100)
        try setCreated(t, "Pictures/x.zip", daysAgo: 50)
        let groups = scan(t)
        let g = try #require(groups.first)
        let oldest = try #require(DuplicateSelection.keeper(g, rule: .oldest, home: t.home))
        #expect(oldest.path.hasSuffix("Documents/Archive/x.zip"))
        let newest = try #require(DuplicateSelection.keeper(g, rule: .newest, home: t.home))
        #expect(newest.path.hasSuffix("Pictures/x.zip"))
        #expect(DuplicateSelection.keeper(g, rule: .manual, home: t.home) == nil)

        let sel = DuplicateSelection.automatic(groups, rule: .oldest, home: t.home)
        #expect(sel.ticked(in: g).count == 3)
        #expect(!sel.contains(oldest))
        #expect(DuplicateSelection.automatic(groups, rule: .manual, home: t.home).paths.isEmpty)
    }

    @Test func tieBreakIsShortestPath() throws {
        let t = try TestHome("dup-tie")
        defer { t.cleanUp() }
        let a = Self.data(Self.mb + 5)
        try t.file("Documents/deep/er/x.bin", contents: a)
        try t.file("Documents/x.bin", contents: a)
        let same = Date(timeIntervalSince1970: 1_700_000_000)
        for rel in ["Documents/deep/er/x.bin", "Documents/x.bin"] {
            try FileManager.default.setAttributes([.creationDate: same], ofItemAtPath: t.path(rel))
        }
        let g = try #require(scan(t).first)
        #expect(DuplicateSelection.keeper(g, rule: .oldest, home: t.home)?.path.hasSuffix("Documents/x.bin") == true)
    }

    @Test func theLastCopyCanNeverBeTicked() throws {
        let t = try TestHome("dup-last")
        defer { t.cleanUp() }
        let a = Self.data(Self.mb + 7)
        try t.file("Documents/a.bin", contents: a)
        try t.file("Music/a.bin", contents: a)
        let g = try #require(scan(t).first)
        var sel = DuplicateSelection()
        let first = sel.set(g.files[0], in: g, true)
        #expect(first)
        #expect(!sel.canTick(g.files[1], in: g))
        let last = sel.set(g.files[1], in: g, true)
        #expect(!last, "ticking the last copy is refused")
        #expect(sel.ticked(in: g).count == 1)
        sel.set(g.files[0], in: g, false)
        let other = sel.set(g.files[1], in: g, true)
        #expect(other)
    }

    @Test func hashCacheIsUsedAndRefreshedOnChange() throws {
        let t = try TestHome("dup-cache")
        defer { t.cleanUp() }
        let cache = try HashCache(url: HashCache.defaultURL(home: t.home))
        #expect(cache.url.path.hasSuffix("Library/Application Support/TidyMyMac/Cache/hashes.sqlite"))
        let a = Self.data(Self.mb + 64 * 1024)
        try t.file("Documents/a.bin", contents: a)
        try t.file("Movies/a.bin", contents: a)
        #expect(scan(t, cache: cache).count == 1)
        #expect(cache.count == 2)

        let entry = try #require(ClutterWalker(home: t.home).files(.defaults(t.home), includePackages: false).first)
        let key = HashCache.Key(path: entry.path, size: entry.size, modified: entry.modified, inode: entry.identity.inode)
        let cached = try #require(cache.lookup(key))
        #expect(cached.partial != nil && cached.full != nil)

        // A changed file (new modification date) misses the cache, so it is hashed again.
        var b = a
        b[a.count / 2] ^= 0x1
        try t.file("Movies/a.bin", contents: b)
        try t.setModified("Movies/a.bin", daysAgo: 1)
        #expect(scan(t, cache: cache).isEmpty)

        try cache.clear()
        #expect(cache.count == 0)
    }

    @Test func duplicateDownloadsNeedARealHashMatch() throws {
        let t = try TestHome("dup-downloads")
        defer { t.cleanUp() }
        let a = Self.data(Self.mb + 3)
        try t.file("Downloads/invoice.pdf", contents: a)
        try t.file("Documents/Taxes/invoice.pdf", contents: a)
        try t.file("Downloads/photo (1).jpg", contents: Self.data(Self.mb + 9, seed: 4))
        try t.file("Downloads/photo.jpg", contents: Self.data(Self.mb + 9, seed: 5))
        // Two identical copies inside Downloads only: not "elsewhere".
        try t.file("Downloads/both/a.iso", contents: Self.data(Self.mb + 11, seed: 6))
        try t.file("Downloads/a.iso", contents: Self.data(Self.mb + 11, seed: 6))
        // A duplicate pair entirely outside Downloads is ignored by this pass.
        try t.file("Music/z.bin", contents: Self.data(Self.mb + 13, seed: 7))
        try t.file("Movies/z.bin", contents: Self.data(Self.mb + 13, seed: 7))

        let downloads = try #require(PathNormalizer.realPath(t.home.downloads.path))
        let files = ClutterWalker(home: t.home).files(.defaults(t.home), includePackages: false)
        let groups = DuplicateFinder(cache: nil).groups(files, requireUnder: downloads)
        #expect(groups.count == 2, "the Music/Movies pair is never hashed")
        let items = DownloadsReview.markDuplicates(DownloadsReview.items(home: t.home), groups: groups, downloads: downloads)
        let flagged = items.filter { !$0.alsoElsewhere.isEmpty }.map(\.name)
        #expect(flagged == ["invoice.pdf"])
        #expect(items.first { $0.name == "invoice.pdf" }?.alsoElsewhere.first?.hasSuffix("Documents/Taxes/invoice.pdf") == true)
    }
}
