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

    /// iCloud placeholder: reading it would download the file (`SF_DATALESS`).
    public var isDataless: Bool { flags & 0x4000_0000 != 0 }

    /// The APFS clone family id, only for files that share blocks with a clone.
    public static func cloneID(_ path: String) -> UInt64? {
        var al = attrlist()
        al.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        al.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        al.forkattr = attrgroup_t(ATTR_CMNEXT_CLONEID | ATTR_CMNEXT_EXT_FLAGS)
        var buf = [UInt8](repeating: 0, count: 64)
        guard getattrlist(path, &al, &buf, buf.count, UInt32(FSOPT_NOFOLLOW | FSOPT_ATTR_CMN_EXTENDED)) == 0 else { return nil }
        return buf.withUnsafeBytes { raw -> UInt64? in
            var off = 4
            let returned = raw.loadUnaligned(fromByteOffset: off, as: attribute_set_t.self)
            off += MemoryLayout<attribute_set_t>.size
            guard returned.forkattr & attrgroup_t(ATTR_CMNEXT_CLONEID) != 0,
                  returned.forkattr & attrgroup_t(ATTR_CMNEXT_EXT_FLAGS) != 0 else { return nil }
            let clone = raw.loadUnaligned(fromByteOffset: off, as: UInt64.self)
            let flags = raw.loadUnaligned(fromByteOffset: off + 8, as: UInt64.self)
            return flags & UInt64(EF_MAY_SHARE_BLOCKS) != 0 ? clone : nil
        }
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
