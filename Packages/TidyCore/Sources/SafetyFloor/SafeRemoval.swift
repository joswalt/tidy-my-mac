import Darwin
import Foundation

/// Removal by file descriptor: every step is opened relative to its parent with O_NOFOLLOW, so
/// swapping a folder for a symlink after the scan can't redirect the action, and nothing crosses
/// onto another volume (005 §5.3). Equivalent to fts with FTS_PHYSICAL | FTS_XDEV.
/// Shared by the helper and the app's remover (security review finding 1).
public enum SafeRemoval {
    public struct Failure: Error, CustomStringConvertible {
        public let message: String
        public var description: String { message }
        public init(message: String) { self.message = message }
        public static func errno(_ what: String) -> Failure { Failure(message: "\(what): \(String(cString: strerror(Darwin.errno)))") }
    }

    public static func lstatAt(_ dirfd: Int32, _ name: String) -> stat? {
        var st = stat()
        return fstatat(dirfd, name, &st, AT_SYMLINK_NOFOLLOW) == 0 ? st : nil
    }

    /// Opens a directory relative to `dirfd` without following a symlink.
    public static func openDir(_ dirfd: Int32, _ name: String) -> Int32 {
        openat(dirfd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    }

    /// Opens an absolute directory path one component at a time, never following a symlink.
    public static func openPath(_ path: String) -> Int32 {
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
    public static func precheck(_ dirfd: Int32, _ name: String, device: Int32) throws {
        guard let st = lstatAt(dirfd, name) else { throw Failure.errno("stat \(name)") }
        if st.st_dev != device { throw Failure(message: "it contains another volume") }
        if st.st_flags & FileStatus.lockedFlags != 0 { throw Failure(message: "it contains a locked item") }
        guard st.st_mode & S_IFMT == S_IFDIR else { return }
        if ProtectedFloor.libraryExtensions.contains(PathNormalizer.fold((name as NSString).pathExtension)) {
            throw Failure(message: "it contains a media library")
        }
        let fd = openDir(dirfd, name)
        guard fd >= 0 else { throw Failure.errno("open \(name)") }
        defer { close(fd) }
        for child in try names(fd) { try precheck(fd, child, device: device) }
    }

    /// Deletes `name` inside `dirfd`, depth first.
    public static func removeTree(_ dirfd: Int32, _ name: String, device: Int32) throws {
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

    public static func names(_ fd: Int32) throws -> [String] {
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

    /// "x 2.ext", "x 3.ext"… for the nth try at a free name in the Trash.
    public static func numberedName(_ name: String, _ n: Int) -> String {
        let ns = name as NSString
        let ext = ns.pathExtension
        return ns.deletingPathExtension + " \(n)" + (ext.isEmpty ? "" : "." + ext)
    }

    /// Opens an absolute directory path one component at a time without following a symlink,
    /// except that the first component may be a system link (/var, /tmp, /etc → /private): those
    /// are root-owned. For the app, whose paths can sit under the temp or cache folders.
    public static func openPathAllowingSystemLink(_ path: String) -> Int32 {
        let comps = path.split(separator: "/").map(String.init)
        guard let first = comps.first else { return open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC) }
        let root = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard root >= 0 else { return -1 }
        // Only a root-owned link at the top level is followed.
        if let st = lstatAt(root, first), st.st_mode & S_IFMT == S_IFLNK, st.st_uid != 0 { close(root); return -1 }
        var fd = openat(root, first, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        close(root)
        guard fd >= 0 else { return -1 }
        for comp in comps.dropFirst() {
            let next = openDir(fd, comp)
            close(fd)
            guard next >= 0 else { return -1 }
            fd = next
        }
        return fd
    }

    /// Permanently deletes the reviewed item at `path`, bound to its identity: the parent is
    /// opened by descriptor without following links, the name must still be the same object
    /// (device and inode) and not a symlink unless `allowSymlink`, the tree is prechecked (no
    /// locked item, no media library, no other volume), and everything is removed relative to
    /// descriptors. A folder swapped for a symlink at any depth is never followed.
    public static func removeVerified(_ path: String, identity: ItemIdentity, allowSymlink: Bool = false) throws {
        guard let n = PathNormalizer.normalize(path), n != "/" else { throw Failure(message: "not a removable path") }
        try TestFence.check(n)
        let name = (n as NSString).lastPathComponent
        let parent = openPathAllowingSystemLink((n as NSString).deletingLastPathComponent)
        guard parent >= 0 else { throw Failure(message: "its folder can't be opened without following a link") }
        defer { close(parent) }
        guard let st = lstatAt(parent, name) else { throw Failure(message: "the item no longer exists") }
        guard st.st_dev == identity.device, st.st_ino == identity.inode else { throw Failure(message: "the item was replaced since the scan") }
        if st.st_mode & S_IFMT == S_IFLNK {
            guard allowSymlink else { throw Failure(message: "the item became a symbolic link") }
            guard unlinkat(parent, name, 0) == 0 else { throw Failure.errno("remove \(name)") }
            return
        }
        try precheck(parent, name, device: st.st_dev)
        try removeTree(parent, name, device: st.st_dev)
    }
}
