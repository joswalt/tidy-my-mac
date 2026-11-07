import CryptoKit
import Darwin
import Foundation
import SafetyFloor

/// One copy in a duplicate set.
public struct DuplicateFile: Sendable, Hashable, Identifiable {
    public let entry: FileEntry
    /// APFS clone family, when the file shares blocks with a clone.
    public let cloneID: UInt64?

    public init(entry: FileEntry, cloneID: UInt64?) {
        self.entry = entry
        self.cloneID = cloneID
    }

    public var id: String { entry.path }
    public var path: String { entry.path }
}

/// Files with the same full SHA-256 (spec 014 §1). Hard links are one file and never appear twice.
public struct DuplicateGroup: Sendable, Hashable, Identifiable {
    /// Hex of the full-file SHA-256.
    public let id: String
    public let size: Int64
    public let files: [DuplicateFile]

    public init(id: String, size: Int64, files: [DuplicateFile]) {
        self.id = id
        self.size = size
        self.files = files
    }

    /// An APFS clone of another copy in the set: removing it frees ~0 KB (spec 014 §2).
    public func sharesSpace(_ file: DuplicateFile) -> Bool {
        guard let c = file.cloneID else { return false }
        return files.contains { $0.path != file.path && $0.cloneID == c }
    }

    /// What removing every copy but one would free: clones count once.
    public var reclaimableBytes: Int64 {
        var seenClones: Set<UInt64> = []
        var total: Int64 = 0
        for f in files {
            if let c = f.cloneID, !seenClones.insert(c).inserted { continue }
            total += f.entry.allocatedBytes
        }
        return max(0, total - (files.map(\.entry.allocatedBytes).max() ?? 0))
    }

    public var name: String { files.first?.entry.name ?? "" }
}

/// Size → SHA-256 of the first and last 16 KB → full SHA-256 (spec 014 §1).
public struct DuplicateFinder: Sendable {
    public static let edgeBytes = 16 * 1024
    public let cache: HashCache?

    public init(cache: HashCache?) { self.cache = cache }

    public struct Progress: Sendable {
        public var hashed: Int
        public var toHash: Int
    }

    /// Groups `files` into duplicate sets. With `requireUnder`, only sets with at least one copy
    /// inside that folder are kept (duplicate downloads, spec 014 §8). Packages are never compared.
    public func groups(_ files: [FileEntry], requireUnder: String? = nil,
                       progress: (@Sendable (Progress) -> Void)? = nil,
                       isCancelled: @Sendable () -> Bool = { false }) -> [DuplicateGroup] {
        // Hard links share an inode: one file (the walker already drops repeats; this is a guard).
        var byIdentity: [ItemIdentity: FileEntry] = [:]
        for f in files where !f.isPackage && f.size > 0 { byIdentity[f.identity] = byIdentity[f.identity] ?? f }
        var bySize = Dictionary(grouping: byIdentity.values, by: \.size).filter { $0.value.count > 1 }
        if let under = requireUnder {
            bySize = bySize.filter { $0.value.contains { PathNormalizer.isInside($0.path, under) } }
        }
        var p = Progress(hashed: 0, toHash: bySize.values.reduce(0) { $0 + $1.count })
        progress?(p)

        var result: [DuplicateGroup] = []
        for (size, sameSize) in bySize {
            if isCancelled() { return [] }
            var byPartial: [Data: [FileEntry]] = [:]
            for f in sameSize {
                if let h = hash(f, full: false) { byPartial[h, default: []].append(f) }
                p.hashed += 1
                if p.hashed % 16 == 0 { progress?(p) }
            }
            for candidates in byPartial.values where candidates.count > 1 {
                // Files that fit in the two edges were read whole already.
                let needsFull = size > Int64(2 * Self.edgeBytes)
                var byFull: [Data: [FileEntry]] = [:]
                for f in candidates {
                    if isCancelled() { return [] }
                    if let h = needsFull ? hash(f, full: true) : hash(f, full: false) { byFull[h, default: []].append(f) }
                }
                for (h, same) in byFull where same.count > 1 {
                    let members = same.sorted { $0.path < $1.path }.map { DuplicateFile(entry: $0, cloneID: FileStatus.cloneID($0.path)) }
                    result.append(DuplicateGroup(id: h.map { String(format: "%02x", $0) }.joined(), size: size, files: members))
                }
            }
        }
        progress?(p)
        return result.sorted { ($0.reclaimableBytes, $0.id) > ($1.reclaimableBytes, $1.id) }
    }

    /// Cached when possible. nil if the file can't be read or changed under us.
    func hash(_ f: FileEntry, full: Bool) -> Data? {
        let key = HashCache.Key(path: f.path, size: f.size, modified: f.modified, inode: f.identity.inode)
        if let cached = cache?.lookup(key), let h = full ? cached.full : cached.partial { return h }
        guard let h = Self.compute(f, full: full) else { return nil }
        cache?.store(key, partial: full ? nil : h, full: full ? h : nil)
        return h
    }

    /// Reads without following links and checks it is still the same file.
    static func compute(_ f: FileEntry, full: Bool) -> Data? {
        let fd = open(f.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_ino == f.identity.inode, st.st_dev == f.identity.device, st.st_size == f.size else { return nil }
        _ = fcntl(fd, F_NOCACHE, 1)
        var hasher = SHA256()
        let chunk = 1 << 20
        var buf = [UInt8](repeating: 0, count: chunk)
        func read(at offset: Int64, count: Int) -> Bool {
            var done = 0
            while done < count {
                let n = buf.withUnsafeMutableBytes { pread(fd, $0.baseAddress, min(chunk, count - done), off_t(offset) + off_t(done)) }
                if n <= 0 { return false }
                hasher.update(data: buf[0..<n])
                done += n
            }
            return true
        }
        let size = f.size
        if full || size <= Int64(2 * edgeBytes) {
            guard read(at: 0, count: Int(size)) else { return nil }
        } else {
            guard read(at: 0, count: edgeBytes), read(at: size - Int64(edgeBytes), count: edgeBytes) else { return nil }
        }
        return Data(hasher.finalize())
    }
}

/// Which copy each set keeps when ticking automatically (spec 014 §6).
public enum KeepRule: String, CaseIterable, Sendable, Identifiable {
    /// The copy outside Downloads and Desktop first, then the oldest, then the shortest path.
    case oldest
    /// The copy outside Downloads and Desktop first, then the newest, then the shortest path.
    case newest
    /// Nothing ticked: John picks.
    case manual

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oldest: "Keep Oldest"
        case .newest: "Keep Newest"
        case .manual: "Choose Myself"
        }
    }
}

/// Ticked copies in duplicate sets. The last copy of a set can never be ticked (spec 014 §6).
public struct DuplicateSelection: Sendable, Equatable {
    public private(set) var paths: Set<String> = []

    public init(paths: Set<String> = []) { self.paths = paths }

    /// The copy a set keeps under `rule` (nil for `manual`).
    public static func keeper(_ group: DuplicateGroup, rule: KeepRule, home: Home) -> DuplicateFile? {
        let transient = [home.downloads.path, home.desktop.path].compactMap { PathNormalizer.realPath($0) ?? $0 }
        func outside(_ f: DuplicateFile) -> Int { transient.contains { PathNormalizer.isInside(f.path, $0) } ? 1 : 0 }
        switch rule {
        case .manual: return nil
        case .oldest, .newest:
            return group.files.min { a, b in
                if outside(a) != outside(b) { return outside(a) < outside(b) }
                if a.entry.created != b.entry.created {
                    return rule == .oldest ? a.entry.created < b.entry.created : a.entry.created > b.entry.created
                }
                if a.path.count != b.path.count { return a.path.count < b.path.count }
                return a.path < b.path
            }
        }
    }

    /// Ticks every copy but the keeper; clones of a kept copy stay unticked (they free ~0 KB).
    public static func automatic(_ groups: [DuplicateGroup], rule: KeepRule, home: Home) -> DuplicateSelection {
        var s = DuplicateSelection()
        for g in groups {
            guard let keep = keeper(g, rule: rule, home: home) else { continue }
            for f in g.files where f.path != keep.path && !g.sharesSpace(f) { s.paths.insert(f.path) }
        }
        return s
    }

    public func contains(_ f: DuplicateFile) -> Bool { paths.contains(f.path) }

    /// Ticking the last unticked copy of a set is refused.
    public func canTick(_ f: DuplicateFile, in group: DuplicateGroup) -> Bool {
        contains(f) || group.files.filter { !contains($0) }.count > 1
    }

    /// Returns false (and changes nothing) when the tick would leave no copy.
    @discardableResult
    public mutating func set(_ f: DuplicateFile, in group: DuplicateGroup, _ on: Bool) -> Bool {
        if !on { paths.remove(f.path); return true }
        guard canTick(f, in: group) else { return false }
        paths.insert(f.path)
        return true
    }

    public func ticked(in group: DuplicateGroup) -> [DuplicateFile] { group.files.filter(contains) }

    /// Space the ticked copies free: clones of a copy that stays free nothing.
    public func freedBytes(_ groups: [DuplicateGroup]) -> Int64 {
        groups.reduce(0) { total, g in
            let kept = g.files.filter { !contains($0) }
            let keptClones = Set(kept.compactMap(\.cloneID))
            var seen: Set<UInt64> = []
            var bytes: Int64 = 0
            for f in g.files where contains(f) {
                if let c = f.cloneID { if keptClones.contains(c) || !seen.insert(c).inserted { continue } }
                bytes += f.entry.allocatedBytes
            }
            return total + bytes
        }
    }

    public mutating func keepOnly(_ groups: [DuplicateGroup]) {
        paths.formIntersection(groups.flatMap { $0.files.map(\.path) })
    }
}
