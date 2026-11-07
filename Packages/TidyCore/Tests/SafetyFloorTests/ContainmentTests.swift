import Foundation
import Testing
import TestSupport
@testable import SafetyFloor

/// Spec 017 §4.2 path containment cases.
struct ContainmentTests {
    @Test func cases() throws {
        let t = try TestHome("containment")
        defer { t.cleanUp() }
        let root = t.path("Library/Caches")
        try t.file("Library/Caches/app/data")
        try t.file("Documents/secret")
        try t.symlink("Library/Caches/link", to: t.path("Documents"))
        try t.symlink("Library/Caches/linkdir", to: t.path("Documents"))

        #expect(throws: Never.self) { try Containment.validate(item: root + "/app", root: root) }
        #expect(throws: Never.self) { try Containment.validate(item: root + "/app/data", root: root) }
        #expect(throws: ContainmentError.dotDot) { try Containment.validate(item: root + "/../../Documents/secret", root: root) }
        #expect(throws: ContainmentError.equalsRoot) { try Containment.validate(item: root, root: root) }
        #expect(throws: ContainmentError.notInsideRoot) { try Containment.validate(item: t.path("Documents/secret"), root: root) }
        #expect(throws: ContainmentError.symlinkedItem) { try Containment.validate(item: root + "/link", root: root) }
        #expect(throws: ContainmentError.symlinkedParent(root + "/linkdir")) {
            try Containment.validate(item: root + "/linkdir/secret", root: root)
        }
        #expect(throws: ContainmentError.missing) { try Containment.validate(item: root + "/gone", root: root) }
        // Case variant of the same folder (APFS is case-insensitive).
        #expect(throws: Never.self) { try Containment.validate(item: root + "/APP", root: root) }
    }

    @Test func otherVolume() {
        // /dev is devfs, a different device from the root volume.
        #expect(throws: ContainmentError.otherVolume) { try Containment.validate(item: "/dev/null", root: "/") }
    }

    @Test func firmlinkSpelling() throws {
        let t = try TestHome("firmlink")
        defer { t.cleanUp() }
        try t.file("Library/Caches/app/data")
        // The same folder reached through /System/Volumes/Data normalizes to the same place.
        let viaData = "/System/Volumes/Data" + t.path("Library/Caches/app")
        #expect(PathNormalizer.normalize(viaData) == PathNormalizer.normalize(t.path("Library/Caches/app")))
    }
}

struct TestHomeAndFenceTests {
    @Test func refusesUnsafeLocations() {
        let tmp = PathNormalizer.realPath(FileManager.default.temporaryDirectory.path)!
        #expect(throws: TestHome.Refused.self) { try TestHome.assertSafe("/", tempDir: tmp) }
        #expect(throws: TestHome.Refused.self) { try TestHome.assertSafe(tmp, tempDir: tmp) }
        #expect(throws: TestHome.Refused.self) { try TestHome.assertSafe("/Users/\(NSUserName())/Documents/x/y", tempDir: tmp) }
        #expect(throws: Never.self) { try TestHome.assertSafe(tmp + "/TidyMyMacTests-x", tempDir: tmp) }
    }

    @Test func fenceBlocksOutsidePaths() throws {
        let t = try TestHome("fence")
        defer { t.cleanUp() }
        #expect(TestFence.isActive)
        #expect(throws: Never.self) { try TestFence.check(t.path("Library/Caches/x")) }
        #expect(throws: TestFence.Violation.self) { try TestFence.check("/Users/\(NSUserName())/Documents") }
        #expect(throws: TestFence.Violation.self) { try TestFence.check(t.base.path + "/../escape") }
    }

    @Test func fixtureLivesInTempDir() throws {
        let t = try TestHome("where")
        defer { t.cleanUp() }
        let tmp = PathNormalizer.realPath(FileManager.default.temporaryDirectory.path)!
        #expect(PathNormalizer.isInside(t.home.root.path, tmp))
        #expect(t.home.root.path != tmp)
    }
}
