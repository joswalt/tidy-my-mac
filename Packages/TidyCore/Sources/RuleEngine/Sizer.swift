import Darwin
import Foundation
import SafetyFloor

/// Measures items by allocated size (spec 006 §5.5). Hard links and APFS clones are counted
/// once across everything one sizer measures, so totals never promise space that won't be freed.
/// Walks with `lstat`, never follows symlinks and never crosses onto another volume.
public final class Sizer: @unchecked Sendable {
    public struct Measure: Equatable, Sendable {
        public var allocatedBytes: Int64 = 0
        public var newestModification: Date = .distantPast
        public var fileCount: Int = 0
        public var containsLockedItem = false
        public var crossesVolume = false
    }

    private var seenLinks: Set<ItemIdentity> = []
    private var seenClones: Set<ItemIdentity> = []
    private let lock = NSLock()

    public init() {}

    public func measure(_ path: String) -> Measure {
        guard let st = FileStatus.lstat(path) else { return Measure() }
        var m = Measure()
        lock.withLock { walk(path, st, device: st.device, into: &m) }
        return m
    }

    private func walk(_ path: String, _ st: FileStatus, device: Int32, into m: inout Measure) {
        if st.device != device { m.crossesVolume = true; return }
        if st.isLocked { m.containsLockedItem = true }
        if st.modified > m.newestModification { m.newestModification = st.modified }
        m.allocatedBytes += countedBytes(path, st)
        guard st.isDirectory, let dir = opendir(path) else {
            if !st.isDirectory { m.fileCount += 1 }
            return
        }
        defer { closedir(dir) }
        while let entry = readdir(dir) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if name == "." || name == ".." { continue }
            let child = path + "/" + name
            if let cst = FileStatus.lstat(child) { walk(child, cst, device: device, into: &m) }
        }
    }

    private func countedBytes(_ path: String, _ st: FileStatus) -> Int64 {
        guard st.isRegularFile else { return st.allocatedBytes }
        if st.linkCount > 1, !seenLinks.insert(st.identity).inserted { return 0 }
        if let clone = Self.cloneID(path), !seenClones.insert(ItemIdentity(device: st.device, inode: clone)).inserted {
            return 0
        }
        return st.allocatedBytes
    }

    /// The APFS clone family id, only for files that share blocks with a clone.
    static func cloneID(_ path: String) -> UInt64? {
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
