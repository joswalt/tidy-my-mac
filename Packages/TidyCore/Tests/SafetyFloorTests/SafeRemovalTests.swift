import Darwin
import Foundation
import Testing
import TestSupport
@testable import SafetyFloor

/// Descriptor-based removal shared by the app and the helper (security review finding 1).
struct SafeRemovalTests {
    func identity(_ path: String) throws -> ItemIdentity { try #require(FileStatus.lstat(path)).identity }

    @Test func removesTheReviewedItem() throws {
        let t = try TestHome("saferemoval-ok")
        defer { t.cleanUp() }
        try t.file("Library/Caches/com.example.App/a/b/c.bin", size: 2000)
        let p = t.path("Library/Caches/com.example.App")
        try SafeRemoval.removeVerified(p, identity: identity(p))
        #expect(FileStatus.lstat(p) == nil)
        #expect(FileStatus.lstat(t.path("Library/Caches")) != nil)
    }

    @Test func refusesWhenAParentFolderWasSwappedForASymlink() throws {
        let t = try TestHome("saferemoval-parent")
        defer { t.cleanUp() }
        try t.file("Library/Caches/Vendor/item/data")
        let p = t.path("Library/Caches/Vendor/item")
        let id = try identity(p)
        // After review, Vendor moves to Documents and a symlink takes its place: the same item
        // (same inode) is now reachable only through the link. It must not be removed.
        try t.folder("Documents")
        guard rename(t.path("Library/Caches/Vendor"), t.path("Documents/Vendor")) == 0 else { Issue.record("rename"); return }
        try t.symlink("Library/Caches/Vendor", to: t.path("Documents/Vendor"))
        #expect(throws: SafeRemoval.Failure.self) { try SafeRemoval.removeVerified(p, identity: id) }
        #expect(FileStatus.lstat(t.path("Documents/Vendor/item/data")) != nil)
    }

    @Test func refusesAReplacedItem() throws {
        let t = try TestHome("saferemoval-replaced")
        defer { t.cleanUp() }
        try t.file("Library/Caches/x/old")
        let p = t.path("Library/Caches/x")
        let id = try identity(p)
        try t.remove("Library/Caches/x")
        try t.file("Library/Caches/x/unreviewed")
        #expect(throws: SafeRemoval.Failure.self) { try SafeRemoval.removeVerified(p, identity: id) }
        #expect(FileStatus.lstat(t.path("Library/Caches/x/unreviewed")) != nil)
    }

    @Test func aNestedFolderSwappedForASymlinkIsUnlinkedNotFollowed() throws {
        let t = try TestHome("saferemoval-nested")
        defer { t.cleanUp() }
        try t.file("Library/Caches/y/sub/data")
        try t.file("Documents/precious/keep.txt")
        let p = t.path("Library/Caches/y")
        let id = try identity(p)
        try t.remove("Library/Caches/y/sub")
        try t.symlink("Library/Caches/y/sub", to: t.path("Documents/precious"))
        try SafeRemoval.removeVerified(p, identity: id)
        #expect(FileStatus.lstat(p) == nil)
        #expect(FileStatus.lstat(t.path("Documents/precious/keep.txt")) != nil)
    }

    @Test func aTopLevelSymlinkIsRefusedOrRemovedAsALink() throws {
        let t = try TestHome("saferemoval-link")
        defer { t.cleanUp() }
        try t.file("Documents/precious/keep.txt")
        try t.symlink(".Trash/link", to: t.path("Documents/precious"))
        let p = t.path(".Trash/link")
        let id = try identity(p)
        #expect(throws: SafeRemoval.Failure.self) { try SafeRemoval.removeVerified(p, identity: id) }
        try SafeRemoval.removeVerified(p, identity: id, allowSymlink: true)
        #expect(FileStatus.lstat(p) == nil)
        #expect(FileStatus.lstat(t.path("Documents/precious/keep.txt")) != nil)
    }

    @Test func refusesATreeHoldingAMediaLibrary() throws {
        let t = try TestHome("saferemoval-library")
        defer { t.cleanUp() }
        try t.file("Library/Caches/z/Old.photoslibrary/database/db")
        let p = t.path("Library/Caches/z")
        #expect(throws: SafeRemoval.Failure.self) { try SafeRemoval.removeVerified(p, identity: try identity(p)) }
        #expect(FileStatus.lstat(t.path("Library/Caches/z/Old.photoslibrary/database/db")) != nil)
    }

    @Test func onlyARootOwnedTopLevelLinkIsFollowed() throws {
        // /var → /private/var is root-owned: allowed for the app's temp and cache paths.
        let fd = SafeRemoval.openPathAllowingSystemLink("/var/tmp")
        #expect(fd >= 0)
        if fd >= 0 { close(fd) }
        #expect(SafeRemoval.openPath("/var/tmp") < 0, "the strict helper variant follows nothing")
        // A link below the top level is never followed.
        let t = try TestHome("saferemoval-open")
        defer { t.cleanUp() }
        try t.folder("Real")
        try t.symlink("Link", to: t.path("Real"))
        #expect(SafeRemoval.openPathAllowingSystemLink(t.path("Link")) < 0)
    }
}
