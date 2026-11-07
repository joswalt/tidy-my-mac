import CoreGraphics
import Darwin
import Foundation
import Testing
import TestSupport
@testable import DiskAnalysis
@testable import RuleEngine
import RunLog
import SafetyFloor

/// Large & Old filters, Downloads review, the treemap layout and removal of hand-picked items.
struct ClutterTests {
    static let mb: Int64 = 1_000_000
    static let rules = try! RuleLoader.load(from: RepoPaths.rules, version: 7)

    func entry(_ path: String, mb: Int64, daysOld: Double) -> FileEntry {
        let d = Date().addingTimeInterval(-daysOld * 86_400)
        return FileEntry(path: path, root: "/x", identity: ItemIdentity(device: 1, inode: UInt64(path.hashValue.magnitude)),
                         isPackage: false, size: mb * Self.mb, allocatedBytes: mb * Self.mb, modified: d, created: d)
    }

    // MARK: Large & Old (build spec §6.6)

    @Test func largeAndOldDefaultFilter() {
        let files = [
            entry("/x/big-new.mov", mb: 150, daysOld: 3),        // large
            entry("/x/mid-old.zip", mb: 60, daysOld: 400),       // old
            entry("/x/mid-new.zip", mb: 60, daysOld: 30),        // neither
            entry("/x/small-old.pdf", mb: 10, daysOld: 900),     // under the 50 MB list minimum
        ]
        let shown = LargeOldFilter.default.apply(files).map { ($0.path as NSString).lastPathComponent }
        #expect(shown == ["big-new.mov", "mid-old.zip"])

        var both = LargeOldFilter.default
        both.match = .both
        #expect(both.apply(files).isEmpty)

        var anyAge = LargeOldFilter(minimumSize: 50 * Self.mb, olderThanDays: nil)
        #expect(anyAge.apply(files).count == 3)
        anyAge.kinds = [.archives]
        #expect(anyAge.apply(files).map { ($0.path as NSString).lastPathComponent }.sorted() == ["mid-new.zip", "mid-old.zip"])
    }

    @Test func fileKinds() {
        #expect(FileKind.of("/a/b.mov") == .movies)
        #expect(FileKind.of("/a/b.mp3") == .music)
        #expect(FileKind.of("/a/b.heic") == .pictures)
        #expect(FileKind.of("/a/b.zip") == .archives)
        #expect(FileKind.of("/a/b.dmg") == .diskImages)
        #expect(FileKind.of("/a/b.pdf") == .documents)
        #expect(FileKind.of("/a/B.app") == .apps)
        #expect(FileKind.of("/a/noext") == .other)
    }

    @Test func walkerListsPackagesWholeForLargeAndOld() throws {
        let t = try TestHome("lo-packages")
        defer { t.cleanUp() }
        try t.file("Documents/Big.app/Contents/MacOS/bin", size: 600_000)
        try t.file("Documents/Big.app/Contents/Resources/r", size: 600_000)
        try t.file("Movies/clip.mov", size: 1_200_000)
        try t.setModified("Movies/clip.mov", daysAgo: 500)
        let files = ClutterWalker(home: t.home).files(.defaults(t.home), includePackages: true)
        let app = try #require(files.first { $0.name == "Big.app" })
        #expect(app.isPackage)
        #expect(app.allocatedBytes >= 1_200_000)
        let clip = try #require(files.first { $0.name == "clip.mov" })
        #expect(clip.modified < Date().addingTimeInterval(-400 * 86_400))
        #expect(!files.contains { $0.path.contains("Big.app/") }, "nothing inside a package on its own")
    }

    // MARK: Downloads review (build spec §6.7)

    @Test func downloadsReviewTopLevelItems() throws {
        let t = try TestHome("downloads")
        defer { t.cleanUp() }
        try t.file("Downloads/setup.dmg", size: 4096)
        try t.file("Downloads/Folder/inner.txt", size: 9000)
        try t.file("Downloads/.hidden", size: 10)
        let url = try t.file("Downloads/paper.pdf", size: 100)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["https://files.example.org/paper.pdf", "https://example.org/"],
                                                       format: .binary, options: 0)
        _ = plist.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemWhereFroms", $0.baseAddress, plist.count, 0, 0) }

        let items = DownloadsReview.items(home: t.home)
        #expect(items.map(\.name) == ["Folder", "paper.pdf", "setup.dmg"])
        #expect(items.first { $0.name == "paper.pdf" }?.sourceHost == "files.example.org")
        let folder = try #require(items.first { $0.name == "Folder" })
        #expect(folder.isDirectory && folder.allocatedBytes >= 9000)
        #expect(!DownloadsReview.isOld(folder, days: 30))
        #expect(DownloadsReview.isOld(folder, days: 30, now: Date().addingTimeInterval(40 * 86_400)))
    }

    // MARK: Treemap

    @Test func squarifiedLayoutFillsTheRectProportionally() {
        let values: [Double] = [6, 6, 4, 3, 2, 2, 1, 0]
        let rect = CGRect(x: 10, y: 20, width: 600, height: 400)
        let rects = Treemap.layout(values, in: rect)
        #expect(rects.count == values.count)
        #expect(rects[7] == .zero)
        let total = values.reduce(0, +)
        for (v, r) in zip(values, rects) where v > 0 {
            let expected = v / total * Double(rect.width * rect.height)
            #expect(abs(Double(r.width * r.height) - expected) < 1.0)
            #expect(rect.insetBy(dx: -0.01, dy: -0.01).contains(r))
            #expect(max(r.width / r.height, r.height / r.width) < 4, "squarified keeps blocks near square")
        }
        for i in rects.indices where values[i] > 0 {
            for j in rects.indices where j > i && values[j] > 0 {
                #expect(rects[i].intersection(rects[j]).width * rects[i].intersection(rects[j]).height < 0.5)
            }
        }
        #expect(Treemap.layout([1, 2], in: .zero) == [.zero, .zero])
    }

    // MARK: Removal of hand-picked items (spec 014 §5, build spec §6.6–6.8)

    func context(_ t: TestHome) -> CleanupContext {
        CleanupContext(home: t.home, rules: Self.rules, guards: FakeGuards(), hasFullDiskAccess: false,
                       trash: HomeTrash(home: t.home), unloader: nil, appVersion: "1.0 (7)")
    }

    func pick(_ t: TestHome, _ rel: String, root: String, set: [String]? = nil) throws -> ManualPick {
        let st = try #require(FileStatus.lstat(t.path(rel)))
        return ManualPick(path: t.path(rel), root: t.path(root), identity: st.identity, allocatedBytes: st.allocatedBytes,
                          duplicateSet: set?.map(t.path))
    }

    @Test func manualPicksGoToTheTrashAndAreLogged() throws {
        let t = try TestHome("manual-run")
        defer { t.cleanUp() }
        try t.file("Documents/old.mov", size: 5000)
        try t.file("Downloads/thing.zip", size: 3000)
        let picks = [try pick(t, "Documents/old.mov", root: "Documents"), try pick(t, "Downloads/thing.zip", root: "Downloads")]
        let remover = ManualRemover(context: context(t))

        let dry = try remover.run(picks, module: "myClutter", dryRun: true)
        #expect(dry.outcome.done.count == 2)
        #expect(FileStatus.lstat(t.path("Documents/old.mov")) != nil, "a dry run changes nothing")
        #expect(dry.record.header.dryRun)

        let run = try remover.run(picks, module: "myClutter", dryRun: false)
        #expect(run.outcome.done.count == 2)
        #expect(run.outcome.done.allSatisfy { $0.ruleID == "manual" && $0.action == .trash && $0.trashPath != nil })
        #expect(FileStatus.lstat(t.path("Documents/old.mov")) == nil)
        #expect(FileStatus.lstat(t.path(".Trash/old.mov")) != nil)
        #expect(run.record.header.module == "myClutter")
    }

    @Test func manualRemoverRefusesTheLastCopyAndChangedItems() throws {
        let t = try TestHome("manual-guards")
        defer { t.cleanUp() }
        let a = Data(repeating: 7, count: 4000)
        try t.file("Documents/a.bin", contents: a)
        try t.file("Music/a.bin", contents: a)
        let set = ["Documents/a.bin", "Music/a.bin"]
        // Both copies picked (the UI never allows it): the second is refused.
        let both = [try pick(t, "Documents/a.bin", root: "Documents", set: set), try pick(t, "Music/a.bin", root: "Music", set: set)]
        let run = try ManualRemover(context: context(t)).run(both, module: "myClutter", dryRun: false)
        #expect(run.outcome.done.map(\.path) == [t.path("Documents/a.bin")])
        #expect(run.outcome.skipped.first?.reason == "it is the last copy of this file")
        #expect(FileStatus.lstat(t.path("Music/a.bin")) != nil)

        // Replaced since the scan.
        try t.file("Movies/b.bin", size: 100)
        let stale = try pick(t, "Movies/b.bin", root: "Movies")
        try t.remove("Movies/b.bin")
        try t.file("Movies/b.bin", size: 100)
        // Protected: a personal folder itself, and anything in ~/Library/Mobile Documents.
        try t.file("Library/Mobile Documents/x.txt", size: 10)
        let floor = [try pick(t, "Library/Mobile Documents/x.txt", root: "Library")]
        let r2 = try ManualRemover(context: context(t)).run([stale] + floor, module: "spaceLens", dryRun: false)
        #expect(r2.outcome.done.isEmpty)
        #expect(r2.outcome.skipped.count == 2)
        #expect(r2.outcome.skipped[0].reason == "the item was replaced since the scan")
        #expect(r2.outcome.skipped[1].reason?.hasPrefix("protected") == true)
    }

    @Test func manualRemoverNeverFollowsSymlinks() throws {
        let t = try TestHome("manual-link")
        defer { t.cleanUp() }
        try t.file("Projects/real/keep.txt", size: 10)
        try t.symlink("Documents/via", to: t.path("Projects/real"))
        let st = try #require(FileStatus.lstat(t.path("Projects/real/keep.txt")))
        let p = ManualPick(path: t.path("Documents/via/keep.txt"), root: t.path("Documents"), identity: st.identity, allocatedBytes: 10)
        let run = try ManualRemover(context: context(t)).run([p], module: "spaceLens", dryRun: false)
        #expect(run.outcome.done.isEmpty)
        #expect(FileStatus.lstat(t.path("Projects/real/keep.txt")) != nil)
    }
}
