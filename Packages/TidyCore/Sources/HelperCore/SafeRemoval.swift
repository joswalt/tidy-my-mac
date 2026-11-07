import Darwin
import Foundation
import SafetyFloor

/// Removal by file descriptor: every step is opened relative to its parent with O_NOFOLLOW, so
/// swapping a folder for a symlink after the scan can't redirect the action, and nothing crosses
/// onto another volume (005 §5.3). Equivalent to fts with FTS_PHYSICAL | FTS_XDEV.
enum SafeRemoval {
    struct Failure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
        static func errno(_ what: String) -> Failure { Failure(message: "\(what): \(String(cString: strerror(Darwin.errno)))") }
    }

    static func lstatAt(_ dirfd: Int32, _ name: String) -> stat? {
        var st = stat()
        return fstatat(dirfd, name, &st, AT_SYMLINK_NOFOLLOW) == 0 ? st : nil
    }

    /// Opens a directory relative to `dirfd` without following a symlink.
    static func openDir(_ dirfd: Int32, _ name: String) -> Int32 {
        openat(dirfd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    }

    /// Opens an absolute directory path one component at a time, never following a symlink.
    static func openPath(_ path: String) -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { return -1 }
        for comp in path.split(separator: "/") {
            let next = openDir(fd, String(comp))
            close(fd)
            guard next >= 0 else { return -1 }
            fd = next
        }
        return fd
    }

    /// Checks a tree before removing anything: no locked items, no other volume.
    static func precheck(_ dirfd: Int32, _ name: String, device: Int32) throws {
        guard let st = lstatAt(dirfd, name) else { throw Failure.errno("stat \(name)") }
        if st.st_dev != device { throw Failure(message: "it contains another volume") }
        if st.st_flags & FileStatus.lockedFlags != 0 { throw Failure(message: "it contains a locked item") }
        guard st.st_mode & S_IFMT == S_IFDIR else { return }
        let fd = openDir(dirfd, name)
        guard fd >= 0 else { throw Failure.errno("open \(name)") }
        defer { close(fd) }
        for child in try names(fd) { try precheck(fd, child, device: device) }
    }

    /// Deletes `name` inside `dirfd`, depth first.
    static func removeTree(_ dirfd: Int32, _ name: String, device: Int32) throws {
        guard let st = lstatAt(dirfd, name) else { throw Failure.errno("stat \(name)") }
        if st.st_dev != device { throw Failure(message: "on another volume") }
        if st.st_mode & S_IFMT == S_IFDIR {
            let fd = openDir(dirfd, name)
            guard fd >= 0 else { throw Failure.errno("open \(name)") }
            do {
                for child in try names(fd) { try removeTree(fd, child, device: device) }
            } catch {
                close(fd)
                throw error
            }
            close(fd)
            guard unlinkat(dirfd, name, AT_REMOVEDIR) == 0 else { throw Failure.errno("remove folder \(name)") }
        } else {
            guard unlinkat(dirfd, name, 0) == 0 else { throw Failure.errno("remove \(name)") }
        }
    }

    static func names(_ fd: Int32) throws -> [String] {
        let dupfd = dup(fd)
        guard dupfd >= 0, let dir = fdopendir(dupfd) else { throw Failure.errno("list") }
        defer { closedir(dir) }
        var out: [String] = []
        while let e = readdir(dir) {
            let n = withUnsafeBytes(of: e.pointee.d_name) { String(decoding: $0.prefix(Int(e.pointee.d_namlen)), as: UTF8.self) }
            if n != "." && n != ".." { out.append(n) }
        }
        return out
    }

    /// A free name in `trashDir` for `name` ("x 2", "x 3"…).
    static func freeTrashPath(_ trashDir: String, _ name: String) -> String {
        var dest = trashDir + "/" + name
        var n = 2
        while FileStatus.lstat(dest) != nil {
            let ns = name as NSString
            let ext = ns.pathExtension
            dest = trashDir + "/" + ns.deletingPathExtension + " \(n)" + (ext.isEmpty ? "" : "." + ext)
            n += 1
        }
        return dest
    }
}
