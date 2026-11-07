import Darwin
import Foundation
import SafetyFloor

/// One folder entry as `getattrlistbulk` returns it: what Space Lens needs, without an `lstat`
/// per entry. Never follows symlinks (the bulk call never does).
struct BulkEntry: Sendable {
    let name: String
    let isDirectory: Bool
    let isRegularFile: Bool
    let identity: ItemIdentity
    let linkCount: UInt32
    /// Bytes on disk: `ATTR_FILE_ALLOCSIZE` / `ATTR_DIR_ALLOCSIZE`, the same figure `st_blocks × 512` gives.
    let allocatedBytes: Int64
}

/// Reads a whole folder with `getattrlistbulk(2)`: names, types, identities, link counts and
/// allocated sizes in a few system calls instead of one `lstat` per entry. This is what makes
/// Space Lens fast on folders with millions of files.
enum BulkDirectory {
    static let bufferSize = 256 * 1024

    /// nil when the folder can't be opened (permissions, gone).
    static func read(_ path: String) -> [BulkEntry]? {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_ERROR) | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_DEVID) | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_FILEID)
        list.dirattr = attrgroup_t(ATTR_DIR_ALLOCSIZE)
        list.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }
        var entries: [BulkEntry] = []
        while true {
            let count = getattrlistbulk(fd, &list, buffer, bufferSize, 0)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                return entries.isEmpty ? nil : entries
            }
            var entryStart = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                let length = Int(entryStart.loadUnaligned(as: UInt32.self))
                defer { entryStart += length }
                if let e = parse(entryStart) { entries.append(e) }
            }
        }
        return entries
    }

    /// One packed entry. Order (getattrlist(2)): length, returned attrs, error, then common attrs
    /// in bit order (name, devid, objtype, fileid), then directory attrs, then file attrs.
    private static func parse(_ start: UnsafeRawPointer) -> BulkEntry? {
        var p = start + 4
        let returned = p.loadUnaligned(as: attribute_set_t.self)
        p += MemoryLayout<attribute_set_t>.size
        if returned.commonattr & attrgroup_t(ATTR_CMN_ERROR) != 0 {
            let error = p.loadUnaligned(as: UInt32.self)
            p += 4
            if error != 0 { return nil }
        }
        guard returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 else { return nil }
        let nameRef = p.loadUnaligned(as: attrreference_t.self)
        let namePtr = (p + Int(nameRef.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
        let name = String(cString: namePtr)
        p += MemoryLayout<attrreference_t>.size
        var device: Int32 = 0
        if returned.commonattr & attrgroup_t(ATTR_CMN_DEVID) != 0 { device = p.loadUnaligned(as: Int32.self); p += 4 }
        var type: UInt32 = 0
        if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 { type = p.loadUnaligned(as: UInt32.self); p += 4 }
        var inode: UInt64 = 0
        if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 { inode = p.loadUnaligned(as: UInt64.self); p += 8 }
        var allocated: Int64 = 0
        var links: UInt32 = 1
        if returned.dirattr & attrgroup_t(ATTR_DIR_ALLOCSIZE) != 0 { allocated = p.loadUnaligned(as: Int64.self); p += 8 }
        if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 { links = p.loadUnaligned(as: UInt32.self); p += 4 }
        if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 { allocated = p.loadUnaligned(as: Int64.self); p += 8 }
        guard name != "." && name != ".." else { return nil }
        return BulkEntry(name: name, isDirectory: type == VDIR.rawValue, isRegularFile: type == VREG.rawValue,
                         identity: ItemIdentity(device: device, inode: inode), linkCount: links, allocatedBytes: allocated)
    }
}
