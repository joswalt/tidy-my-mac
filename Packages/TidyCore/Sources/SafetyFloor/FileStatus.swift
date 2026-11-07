import Foundation

/// An `lstat` snapshot (never follows symlinks).
public struct FileStatus: Sendable, Hashable {
    public let device: Int32
    public let inode: UInt64
    public let mode: UInt16
    public let userID: UInt32
    public let linkCount: UInt16
    public let size: Int64
    public let allocatedBytes: Int64
    public let modified: Date
    public let flags: UInt32

    public var isDirectory: Bool { mode & S_IFMT == S_IFDIR }
    public var isSymlink: Bool { mode & S_IFMT == S_IFLNK }
    public var isRegularFile: Bool { mode & S_IFMT == S_IFREG }

    /// Flags that make an item impossible or unsafe to remove (spec 005 §5.1).
    public static let lockedFlags: UInt32 = UInt32(UF_IMMUTABLE | UF_APPEND | SF_IMMUTABLE | SF_APPEND | SF_NOUNLINK | SF_RESTRICTED)
    public var isLocked: Bool { flags & Self.lockedFlags != 0 }

    public var identity: ItemIdentity { ItemIdentity(device: device, inode: inode) }

    public static func lstat(_ path: String) -> FileStatus? {
        var st = stat()
        guard Darwin.lstat(path, &st) == 0 else { return nil }
        let mtime = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1e9)
        return FileStatus(device: st.st_dev, inode: st.st_ino, mode: st.st_mode, userID: st.st_uid,
                          linkCount: st.st_nlink, size: st.st_size, allocatedBytes: Int64(st.st_blocks) * 512,
                          modified: mtime, flags: st.st_flags)
    }
}

/// Device + inode: what an item is, as opposed to where it is.
public struct ItemIdentity: Sendable, Hashable, Codable {
    public let device: Int32
    public let inode: UInt64

    public init(device: Int32, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}
