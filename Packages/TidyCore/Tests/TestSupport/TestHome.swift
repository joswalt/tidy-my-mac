import Darwin
import Foundation
import SafetyFloor

/// A fresh fixture home in the temp dir for one test (spec 017 §2.3). It refuses to start if
/// its folder would land anywhere but the temp dir, and registers the test fence so the
/// remover can't touch anything outside it. Call `cleanUp()` when done.
public final class TestHome: @unchecked Sendable {
    public let base: URL
    public let home: Home
    private var cleaned = false

    public struct Refused: Error, CustomStringConvertible {
        public let description: String
    }

    public init(_ label: String = "home") throws {
        let tmp = FileManager.default.temporaryDirectory
        guard let tmpReal = PathNormalizer.realPath(tmp.path) else { throw Refused(description: "temp dir missing") }
        let base = URL(fileURLWithPath: tmpReal).appendingPathComponent("TidyMyMacTests-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        guard let real = PathNormalizer.realPath(base.path) else { throw Refused(description: "fixture missing") }
        try Self.assertSafe(real, tempDir: tmpReal)

        self.base = URL(fileURLWithPath: real)
        let root = self.base.appendingPathComponent("Users/tidytest", isDirectory: true)
        let tmpDir = self.base.appendingPathComponent("tmp", isDirectory: true)
        let cacheDir = self.base.appendingPathComponent("darwin-cache", isDirectory: true)
        for d in [root, tmpDir, cacheDir] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        home = Home(root: root, temporaryDirectory: tmpDir, userCacheDirectory: cacheDir, userID: getuid())
        TestFence.register(real)
    }

    /// The fixture must be inside the temp dir, never `/`, never the real home outside $TMPDIR.
    public static func assertSafe(_ path: String, tempDir: String) throws {
        guard path != "/", PathNormalizer.components(path).count > 3 else { throw Refused(description: "fixture path \(path) is too shallow") }
        guard PathNormalizer.isInside(path, tempDir), path != tempDir else {
            throw Refused(description: "fixture path \(path) is not inside the temp dir \(tempDir)")
        }
        let user = NSUserName()
        if path.contains("/Users/\(user)/") && !PathNormalizer.isInside(path, tempDir) {
            throw Refused(description: "fixture path \(path) is inside the real home")
        }
    }

    /// Creates a file (and its folders) at a path relative to the home, with `size` bytes.
    @discardableResult
    public func file(_ relative: String, size: Int = 64, contents: Data? = nil) throws -> URL {
        let url = home.root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = contents ?? Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ relative.utf8.count) })
        try data.write(to: url)
        return url
    }

    @discardableResult
    public func folder(_ relative: String) throws -> URL {
        let url = home.root.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func symlink(_ relative: String, to destination: String) throws {
        let url = home.root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
    }

    public func hardLink(_ relative: String, to existingRelative: String) throws {
        let url = home.root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard Darwin.link(path(existingRelative), url.path) == 0 else { throw Refused(description: "link failed: \(errno)") }
    }

    /// An APFS clone (copy-on-write copy) of an existing file.
    public func clone(_ relative: String, of existingRelative: String) throws {
        let url = home.root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard clonefile(path(existingRelative), url.path, 0) == 0 else { throw Refused(description: "clonefile failed: \(errno)") }
    }

    /// Sets the user immutable flag (`chflags uchg`).
    public func lock(_ relative: String) throws {
        guard chflags(path(relative), UInt32(UF_IMMUTABLE)) == 0 else { throw Refused(description: "chflags failed: \(errno)") }
    }

    public func setModified(_ relative: String, daysAgo: Double) throws {
        let date = Date().addingTimeInterval(-daysAgo * 86_400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path(relative))
    }

    public func path(_ relative: String) -> String { home.root.appendingPathComponent(relative).path }

    /// Removes any item inside this fixture by absolute path. Fence-checked.
    public func remove(absolute path: String) throws {
        try TestFence.check(path)
        guard PathNormalizer.isInside(path, base.path) else { throw Refused(description: "\(path) is outside the fixture") }
        try FileManager.default.removeItem(atPath: path)
    }

    /// Removes a fixture item (to simulate changes between scan and run). Fence-checked.
    public func remove(_ relative: String) throws {
        try TestFence.check(path(relative))
        try FileManager.default.removeItem(atPath: path(relative))
    }


    /// Removes the fixture: clears flags first, then deletes the whole temp folder.
    public func cleanUp() {
        guard !cleaned else { return }
        cleaned = true
        TestFence.unregister(base.path)
        if let e = FileManager.default.enumerator(atPath: base.path) {
            while let rel = e.nextObject() as? String {
                let p = base.path + "/" + rel
                if let st = FileStatus.lstat(p), st.flags != 0 { _ = lchflags(p, 0) }
            }
        }
        try? FileManager.default.removeItem(at: base)
    }

    deinit { cleanUp() }
}

/// A home-relative rule root (`~/…`), expanded against whatever `Home` the scanner is given.
public func ruleRoot(_ relative: String) -> String { "~/" + relative }
