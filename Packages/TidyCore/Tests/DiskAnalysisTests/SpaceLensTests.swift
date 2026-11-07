import Darwin
import Foundation
import Testing
import TestSupport
@testable import DiskAnalysis
import SafetyFloor

/// Space Lens sizes match `du -k` on a fixture (milestone 5 "done when", 017 §4.3).
struct SpaceLensTests {
    /// `du -sk` in KB.
    static func du(_ path: String) throws -> Int64 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        p.arguments = ["-sk", path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return Int64(text.split(separator: "\t").first.map(String.init) ?? "") ?? -1
    }

    func fixture(_ t: TestHome) throws -> String {
        try t.file("Lens/a/one.bin", size: 300_000)
        try t.file("Lens/a/two.bin", size: 5)
        try t.file("Lens/a/deeper/three.bin", size: 1_234_567)
        try t.file("Lens/b/.hidden", size: 70_000)
        try t.file("Lens/b/Thing.app/Contents/MacOS/x", size: 200_000)
        try t.file("Lens/b/Thing.app/Contents/Info.plist", size: 900)
        try t.file("Lens/top.txt", size: 12)
        try t.folder("Lens/empty")
        try t.hardLink("Lens/b/one-link.bin", to: "Lens/a/one.bin")
        try t.symlink("Lens/link-to-a", to: t.path("Lens/a"))
        try t.clone("Lens/c/three-clone.bin", of: "Lens/a/deeper/three.bin")
        return t.path("Lens")
    }

    @Test func sizesMatchDuK() throws {
        let t = try TestHome("lens-du")
        defer { t.cleanUp() }
        let root = try fixture(t)
        let tree = try #require(SpaceScanner(floor: ProtectedFloor(home: t.home)).scan(root))
        #expect(tree.allocatedBytes / 1024 == (try Self.du(root)), "whole tree vs du -k")
        for name in ["a", "c", "empty"] {
            let node = try #require(tree.children.first { $0.name == name })
            #expect(node.allocatedBytes / 1024 == (try Self.du(root + "/" + name)), "\(name) vs du -k")
        }
        let deeper = try #require(tree.find(root + "/a/deeper"))
        #expect(deeper.allocatedBytes / 1024 == (try Self.du(root + "/a/deeper")))
    }

    @Test func treeShape() throws {
        let t = try TestHome("lens-shape")
        defer { t.cleanUp() }
        let root = try fixture(t)
        let tree = try #require(SpaceScanner(floor: ProtectedFloor(home: t.home)).scan(root))
        // Largest first.
        #expect(tree.children.map(\.allocatedBytes) == tree.children.map(\.allocatedBytes).sorted(by: >))
        let b = try #require(tree.children.first { $0.name == "b" })
        let app = try #require(b.children.first { $0.name == "Thing.app" })
        #expect(app.kind == .package && app.children.isEmpty, "packages are leaves")
        #expect(b.children.contains { $0.name == ".hidden" }, "Space Lens counts hidden files")
        let link = try #require(tree.children.first { $0.name == "link-to-a" })
        #expect(link.kind == .file, "a symlink is never followed")
        #expect(tree.find(root + "/a/deeper/three.bin")?.ancestry.map(\.name) == ["Lens", "a", "deeper", "three.bin"])
    }

    @Test func unreadableFoldersBecomeOneBlock() throws {
        let t = try TestHome("lens-unreadable")
        defer { t.cleanUp() }
        try t.file("Lens/ok/file", size: 4000)
        try t.file("Lens/secret1/file", size: 4000)
        try t.file("Lens/secret2/file", size: 4000)
        chmod(t.path("Lens/secret1"), 0)
        chmod(t.path("Lens/secret2"), 0)
        defer {
            chmod(t.path("Lens/secret1"), 0o755)
            chmod(t.path("Lens/secret2"), 0o755)
        }
        let tree = try #require(SpaceScanner(floor: ProtectedFloor(home: t.home)).scan(t.path("Lens")))
        let blocks = tree.children.filter { if case .notReadable = $0.kind { true } else { false } }
        #expect(blocks.count == 1)
        #expect(blocks.first?.kind == .notReadable(count: 2))
        #expect(blocks.first?.isItem == false)
        #expect(tree.children.contains { $0.name == "ok" })
    }

    @Test func smallFilesAreLumped() throws {
        let t = try TestHome("lens-small")
        defer { t.cleanUp() }
        for i in 0..<6 { try t.file("Lens/f\(i)", size: (i + 1) * 5000) }
        let tree = try #require(SpaceScanner(floor: ProtectedFloor(home: t.home), filesPerFolder: 3).scan(t.path("Lens")))
        #expect(tree.children.count == 4)
        let lump = try #require(tree.children.first { $0.kind == .smallFiles(count: 3) })
        #expect(!lump.isItem)
        #expect(tree.allocatedBytes / 1024 == (try Self.du(t.path("Lens"))))
    }

    @Test func pickingRespectsTheFloor() throws {
        let t = try TestHome("lens-floor")
        defer { t.cleanUp() }
        try t.file("Documents/report.pdf", size: 100)
        try t.file("Library/Mobile Documents/doc.txt", size: 100)
        let scanner = SpaceScanner(floor: ProtectedFloor(home: t.home))
        let tree = try #require(scanner.scan(t.home.root.path, accountForVolume: false))
        let docs = try #require(tree.find(t.path("Documents")))
        #expect(!scanner.canPick(docs), "a personal folder itself is protected")
        #expect(scanner.canPick(try #require(tree.find(t.path("Documents/report.pdf")))))
        #expect(!scanner.canPick(try #require(tree.find(t.path("Library/Mobile Documents/doc.txt")))))
        #expect(!scanner.canPick(tree), "never the scan root")
        #expect(SpaceScanner.containmentRoot(for: t.path("Documents/report.pdf"), scanRoot: t.home.root.path) == t.home.root.path)
    }
}

extension SpaceLensTests {
    @Test func pruneTakesSizesOffEveryFolderAbove() throws {
        let t = try TestHome("lens-prune")
        defer { t.cleanUp() }
        let root = try fixture(t)
        let tree = try #require(SpaceScanner(floor: ProtectedFloor(home: t.home)).scan(root))
        let three = try #require(tree.find(root + "/a/deeper/three.bin"))
        let before = (tree.allocatedBytes, try #require(tree.find(root + "/a")).allocatedBytes)
        tree.prune([three.path])
        #expect(tree.find(three.path) == nil)
        #expect(tree.allocatedBytes == before.0 - three.allocatedBytes)
        #expect(tree.find(root + "/a")?.allocatedBytes == before.1 - three.allocatedBytes)
    }
}

extension SpaceLensTests {
    /// The parallel walk gives the same tree as one thread, and hard links land on the first path.
    @Test func parallelWalkMatchesOneThread() throws {
        let t = try TestHome("lens-parallel")
        defer { t.cleanUp() }
        let root = try fixture(t)
        for i in 0..<40 { try t.file("Lens/many/d\(i % 7)/sub\(i % 3)/f\(i)", size: 1000 * (i + 1)) }
        func shape(_ n: SpaceNode) -> [String] {
            ["\(n.path)|\(n.allocatedBytes)|\(n.itemCount)"] + n.children.sorted { $0.id < $1.id }.flatMap(shape)
        }
        let floor = ProtectedFloor(home: t.home)
        let one = try #require(SpaceScanner(floor: floor, threads: 1).scan(root))
        for _ in 0..<5 {
            let many = try #require(SpaceScanner(floor: floor, threads: 8).scan(root))
            #expect(shape(many) == shape(one))
            #expect(many.find(root + "/b/one-link.bin")?.allocatedBytes == 0, "the second hard link counts nothing")
        }
        #expect(one.allocatedBytes / 1024 == (try Self.du(root)))
    }

    @Test func cancelledScanReturnsNothing() throws {
        let t = try TestHome("lens-cancel")
        defer { t.cleanUp() }
        let root = try fixture(t)
        #expect(SpaceScanner(floor: ProtectedFloor(home: t.home)).scan(root, isCancelled: { true }) == nil)
    }
}
