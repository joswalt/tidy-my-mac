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
        /// A directory inside (or the item itself) is a media library (`.photoslibrary`, …); not descended into.
        public var containsMediaLibrary = false
        public var crossesVolume = false
    }

    private var seenLinks: Set<ItemIdentity> = []
    private var seenClones: Set<ItemIdentity> = []
    private let lock = NSLock()
    /// Called now and then with the running total of everything this sizer has measured, so a
    /// long scan can show its size counting up.
    private let onProgress: (@Sendable (Int64) -> Void)?
    private var total: Int64 = 0
    private var lastReport = Date.distantPast

    public init(onProgress: (@Sendable (Int64) -> Void)? = nil) {
        self.onProgress = onProgress
    }

    public func measure(_ path: String) -> Measure {
        guard let st = FileStatus.lstat(path) else { return Measure() }
        var m = Measure()
        lock.withLock { walk(path, st, device: st.device, into: &m) }
        return m
    }

    private func walk(_ path: String, _ st: FileStatus, device: Int32, into m: inout Measure) {
        if let onProgress, Date().timeIntervalSince(lastReport) > 0.25 {
            lastReport = Date()
            onProgress(total)
        }
        if st.device != device { m.crossesVolume = true; return }
        if st.isLocked { m.containsLockedItem = true }
        if st.modified > m.newestModification { m.newestModification = st.modified }
        let bytes = countedBytes(path, st)
        m.allocatedBytes += bytes
        total += bytes
        if st.isDirectory,
           ProtectedFloor.libraryExtensions.contains(PathNormalizer.fold((path as NSString).pathExtension)) {
            m.containsMediaLibrary = true
            return
        }
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
        if let clone = FileStatus.cloneID(path), !seenClones.insert(ItemIdentity(device: st.device, inode: clone)).inserted {
            return 0
        }
        return st.allocatedBytes
    }
}
