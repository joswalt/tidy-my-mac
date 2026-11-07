import Darwin
import Foundation
import SafetyFloor

/// One block in Space Lens (build spec §6.8). Built once by `SpaceScanner`, read-only afterwards.
public final class SpaceNode: @unchecked Sendable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case folder
        /// A package or bundle: a leaf, never opened.
        case package
        case file
        /// Small files of a folder lumped together.
        case smallFiles(count: Int)
        /// Folders the scan couldn't read (and, at a volume's top, space it couldn't account for).
        case notReadable(count: Int)
    }

    public let name: String
    public let path: String
    public let kind: Kind
    public let identity: ItemIdentity?
    public internal(set) var allocatedBytes: Int64
    /// Largest first.
    public internal(set) var children: [SpaceNode] = []
    public internal(set) weak var parent: SpaceNode?
    /// Items the scan visited inside this one (files and folders).
    public internal(set) var itemCount: Int = 0

    init(name: String, path: String, kind: Kind, identity: ItemIdentity?, allocatedBytes: Int64) {
        self.name = name
        self.path = path
        self.kind = kind
        self.identity = identity
        self.allocatedBytes = allocatedBytes
    }

    public var id: String {
        switch kind {
        case .smallFiles: path + "/\u{0}small"
        case .notReadable: path + "/\u{0}unreadable"
        default: path
        }
    }

    /// A real item on disk (not a lumped block) that could be picked for removal.
    public var isItem: Bool {
        switch kind {
        case .folder, .package, .file: true
        case .smallFiles, .notReadable: false
        }
    }

    public var canOpen: Bool { kind == .folder && !children.isEmpty }

    /// The chain from the scan root down to this node.
    public var ancestry: [SpaceNode] {
        var chain: [SpaceNode] = [self]
        var p = parent
        while let n = p { chain.insert(n, at: 0); p = n.parent }
        return chain
    }

    /// Takes removed items out of the tree and their sizes off every folder above them.
    public func prune(_ paths: Set<String>) {
        for path in paths {
            guard let node = find(path), let parent = node.parent else { continue }
            parent.children.removeAll { $0 === node }
            var p: SpaceNode? = parent
            while let n = p {
                n.allocatedBytes -= node.allocatedBytes
                n.itemCount -= 1 + node.itemCount
                p = n.parent
            }
            node.parent = nil
        }
    }

    public func find(_ path: String) -> SpaceNode? {
        if self.path == path { return self }
        guard PathNormalizer.isInside(path, self.path) else { return nil }
        for c in children where c.isItem { if let hit = c.find(path) { return hit } }
        return nil
    }
}

/// Measures a folder or volume for Space Lens: allocated sizes, hard links once, packages as
/// leaves, never following links and never entering another mounted volume. Runs as the user,
/// so unreadable folders become one "Not readable" block per folder, never an error.
public struct SpaceScanner: Sendable {
    public let floor: ProtectedFloor
    /// Files kept one by one per folder; the rest become one "smaller files" block.
    public let filesPerFolder: Int

    public init(floor: ProtectedFloor, filesPerFolder: Int = 200) {
        self.floor = floor
        self.filesPerFolder = filesPerFolder
    }

    public struct Progress: Sendable {
        public var bytes: Int64
        public var items: Int
    }

    final class State {
        var seenLinks: Set<ItemIdentity> = []
        var progress = Progress(bytes: 0, items: 0)
        var lastReport = Date.distantPast
        let report: (@Sendable (Progress) -> Void)?
        let isCancelled: @Sendable () -> Bool
        init(report: (@Sendable (Progress) -> Void)?, isCancelled: @escaping @Sendable () -> Bool) {
            self.report = report
            self.isCancelled = isCancelled
        }
        func tick(_ bytes: Int64) {
            progress.bytes += bytes
            progress.items += 1
            if let report, progress.items % 512 == 0, Date().timeIntervalSince(lastReport) > 0.2 {
                lastReport = Date()
                report(progress)
            }
        }
    }

    /// nil when the target isn't a readable folder. With `accountForVolume`, a scan of a volume's
    /// top adds the space the scan couldn't see (other users, system areas, snapshots) to its
    /// "Not readable" block, so the picture adds up to what the disk says is used.
    public func scan(_ target: String, accountForVolume: Bool = true,
                     progress: (@Sendable (Progress) -> Void)? = nil,
                     isCancelled: @escaping @Sendable () -> Bool = { false }) -> SpaceNode? {
        guard let real = PathNormalizer.realPath(target), let st = FileStatus.lstat(real), st.isDirectory else { return nil }
        let state = State(report: progress, isCancelled: isCancelled)
        let name = real == "/" ? "Macintosh HD" : (real as NSString).lastPathComponent
        let root = SpaceNode(name: name, path: real, kind: .folder, identity: st.identity, allocatedBytes: 0)
        guard fill(root, st, state) else { return nil }
        if accountForVolume, Volumes.isMountPoint(real), let used = Volumes.usedBytes(real) {
            let missing = used - root.allocatedBytes
            if missing > used / 100 { addUnreadable(to: root, bytes: missing, count: 0) }
        }
        progress?(state.progress)
        return state.isCancelled() ? nil : root
    }

    /// Reads a folder into `node`. false when it can't be opened.
    @discardableResult
    func fill(_ node: SpaceNode, _ st: FileStatus, _ state: State) -> Bool {
        guard let names = DirectoryReader.open(node.path) else { return false }
        node.allocatedBytes = st.allocatedBytes
        var folders: [SpaceNode] = []
        var files: [SpaceNode] = []
        var unreadable = 0
        var unreadableBytes: Int64 = 0
        var items = 0
        for name in names {
            if state.isCancelled() { return true }
            let path = node.path == "/" ? "/" + name : node.path + "/" + name
            guard let cst = FileStatus.lstat(path) else { continue }
            items += 1
            if cst.isDirectory {
                // Another volume mounted here (/Volumes/…, /System/Volumes/…): not ours to count.
                // A firmlink (/Users on the Data volume) changes device without being a mount point.
                if cst.device != st.device && Volumes.isMountPoint(path) { continue }
                if ClutterWalker.isPackage(name) {
                    var seen = state.seenLinks
                    let bytes = TreeMeasure.allocatedBytes(path, device: cst.device, seen: &seen)
                    state.seenLinks = seen
                    let leaf = SpaceNode(name: name, path: path, kind: .package, identity: cst.identity, allocatedBytes: bytes)
                    files.append(leaf)
                    state.tick(bytes)
                    continue
                }
                let child = SpaceNode(name: name, path: path, kind: .folder, identity: cst.identity, allocatedBytes: 0)
                if fill(child, cst, state) {
                    child.parent = node
                    folders.append(child)
                    items += child.itemCount
                } else {
                    unreadable += 1
                    unreadableBytes += cst.allocatedBytes
                }
            } else {
                var bytes = cst.allocatedBytes
                if cst.isRegularFile && cst.linkCount > 1 && !state.seenLinks.insert(cst.identity).inserted { bytes = 0 }
                files.append(SpaceNode(name: name, path: path, kind: .file, identity: cst.identity, allocatedBytes: bytes))
                state.tick(bytes)
            }
        }
        files.sort { $0.allocatedBytes > $1.allocatedBytes }
        var kept = Array(files.prefix(filesPerFolder))
        let rest = files.dropFirst(filesPerFolder)
        if !rest.isEmpty {
            kept.append(SpaceNode(name: "\(rest.count.formatted()) smaller files", path: node.path, kind: .smallFiles(count: rest.count),
                                  identity: nil, allocatedBytes: rest.reduce(0) { $0 + $1.allocatedBytes }))
        }
        for k in kept { k.parent = node }
        node.children = folders + kept
        node.allocatedBytes += node.children.reduce(0) { $0 + $1.allocatedBytes }
        node.itemCount = items
        if unreadable > 0 { addUnreadable(to: node, bytes: unreadableBytes, count: unreadable) }
        node.children.sort { $0.allocatedBytes > $1.allocatedBytes }
        return true
    }

    func addUnreadable(to node: SpaceNode, bytes: Int64, count: Int) {
        let label = count == 0 ? "Not readable" : "Not readable (\(count) \(count == 1 ? "folder" : "folders"))"
        if let existing = node.children.firstIndex(where: { if case .notReadable = $0.kind { true } else { false } }) {
            let old = node.children[existing]
            guard case .notReadable(let n) = old.kind else { return }
            let merged = SpaceNode(name: n + count == 0 ? "Not readable" : "Not readable (\(n + count) folders)", path: node.path,
                                   kind: .notReadable(count: n + count), identity: nil, allocatedBytes: old.allocatedBytes + bytes)
            merged.parent = node
            node.children[existing] = merged
        } else {
            let n = SpaceNode(name: label, path: node.path, kind: .notReadable(count: count), identity: nil, allocatedBytes: bytes)
            n.parent = node
            node.children.append(n)
        }
        node.allocatedBytes += bytes
        node.children.sort { $0.allocatedBytes > $1.allocatedBytes }
    }

    /// Can Space Lens offer a tick for this node? Items on the protected floor show none (§6.8).
    public func canPick(_ node: SpaceNode) -> Bool {
        node.isItem && node.parent != nil && !floor.verdict(for: node.path, context: .manualPick).isProtected
    }

    /// The containment root for removing `path`: the highest folder above it, inside the scan
    /// root, on the item's own volume (a firmlinked folder such as /Users starts a new one).
    public static func containmentRoot(for path: String, scanRoot: String) -> String? {
        guard let item = FileStatus.lstat(path) else { return nil }
        var dir = (path as NSString).deletingLastPathComponent
        guard let pst = FileStatus.lstat(dir), pst.device == item.device else { return nil }
        while dir != scanRoot && dir != "/" {
            let up = (dir as NSString).deletingLastPathComponent
            guard let ust = FileStatus.lstat(up), ust.device == item.device, PathNormalizer.isInside(up, scanRoot) else { break }
            dir = up
        }
        return dir
    }
}

/// Mounted volumes for the Space Lens picker.
public enum Volumes {
    public struct Volume: Sendable, Hashable, Identifiable {
        public let name: String
        public let path: String
        public var id: String { path }
    }

    /// The startup disk and every mounted, visible volume.
    public static func mounted() -> [Volume] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey],
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.map { url in
            let name = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? url.lastPathComponent
            return Volume(name: name, path: url.path)
        }
    }

    public static func isMountPoint(_ path: String) -> Bool {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return false }
        let mount = withUnsafeBytes(of: fs.f_mntonname) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return mount == path
    }

    /// Used space as the volume reports it.
    public static func usedBytes(_ path: String) -> Int64? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        return (Int64(fs.f_blocks) - Int64(fs.f_bfree)) * Int64(fs.f_bsize)
    }
}
