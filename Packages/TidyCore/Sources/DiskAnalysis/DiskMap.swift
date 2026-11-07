import Darwin
import Foundation
import SafetyFloor

/// One block in Disk Map (build spec §6.8). Built once by `SpaceScanner`, read-only afterwards.
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

/// Measures a folder or volume for Disk Map: allocated sizes, hard links once, packages as
/// leaves, never following links and never entering another mounted volume. Runs as the user,
/// so unreadable folders become one "Not readable" block per folder, never an error.
///
/// Fast on big folders: each folder is read with `getattrlistbulk` (no `lstat` per file), and a
/// small pool of threads reads folders and packages side by side, at any depth. A folder is
/// finished (sorted, small files lumped) once all its subfolders are. Hard links are settled
/// after the walk, so the result never depends on thread timing: the first path keeps the bytes.
public struct SpaceScanner: Sendable {
    public let floor: ProtectedFloor
    /// Files kept one by one per folder; the rest become one "smaller files" block.
    public let filesPerFolder: Int
    /// Threads reading folders at once. Reading metadata waits on the disk more than the CPU,
    /// so a few more than the core count.
    public let threads: Int

    public static var defaultThreads: Int { min(16, max(4, ProcessInfo.processInfo.activeProcessorCount * 2)) }

    public init(floor: ProtectedFloor, filesPerFolder: Int = 200, threads: Int = SpaceScanner.defaultThreads) {
        self.floor = floor
        self.filesPerFolder = filesPerFolder
        self.threads = max(1, threads)
    }

    public struct Progress: Sendable {
        public var bytes: Int64
        public var items: Int
    }

    /// A hard-linked file seen during the walk, and the block that counted its bytes.
    struct LinkClaim {
        let path: String
        let bytes: Int64
        let holder: SpaceNode
    }

    /// Shared by the walking threads; every field behind `lock`.
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var progress = Progress(bytes: 0, items: 0)
        private var lastReport = Date.distantPast
        private var links: [ItemIdentity: [LinkClaim]] = [:]
        let report: (@Sendable (Progress) -> Void)?
        let isCancelled: @Sendable () -> Bool
        init(report: (@Sendable (Progress) -> Void)?, isCancelled: @escaping @Sendable () -> Bool) {
            self.report = report
            self.isCancelled = isCancelled
        }

        func tick(bytes: Int64, items: Int) {
            lock.lock()
            progress.bytes += bytes
            progress.items += items
            var snapshot: Progress?
            if report != nil, Date().timeIntervalSince(lastReport) > 0.2 {
                lastReport = Date()
                snapshot = progress
            }
            lock.unlock()
            if let snapshot { report?(snapshot) }
        }

        func claim(_ identity: ItemIdentity, _ claim: LinkClaim) {
            lock.lock()
            links[identity, default: []].append(claim)
            lock.unlock()
        }

        var current: Progress { lock.withLock { progress } }
        var allLinks: [ItemIdentity: [LinkClaim]] { lock.withLock { links } }
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
        let walk = Walk(scanner: self, state: state)
        guard walk.run(root: Folder(node: root, ownBytes: st.allocatedBytes, device: st.device, parent: nil, index: 0)),
              !state.isCancelled() else { return nil }
        Self.settleHardLinks(state.allLinks)
        if accountForVolume, Volumes.isMountPoint(real), let used = Volumes.usedBytes(real) {
            let missing = used - root.allocatedBytes
            if missing > used / 100 { addUnreadable(to: root, bytes: missing, count: 0) }
        }
        progress?(state.current)
        return state.isCancelled() ? nil : root
    }

    /// A folder being filled. Its subfolders and packages are separate jobs; when the last one
    /// reports back, the folder is finished and reports to its own parent.
    final class Folder: @unchecked Sendable {
        let node: SpaceNode
        let ownBytes: Int64
        let device: Int32
        let parent: Folder?
        /// This folder's place in its parent's `subjobs`.
        let index: Int
        // Set while reading, before any subjob starts; then only `opened`/`pending` change, under `lock`.
        var files: [SpaceNode] = []
        var linked: [(node: SpaceNode, identity: ItemIdentity)] = []
        var subjobs: [SpaceNode] = []
        var subjobBytes: [Int64] = []
        var items = 0
        var opened: [Bool] = []
        var pending = 0
        let lock = NSLock()

        init(node: SpaceNode, ownBytes: Int64, device: Int32, parent: Folder?, index: Int) {
            self.node = node; self.ownBytes = ownBytes; self.device = device; self.parent = parent; self.index = index
        }
    }

    enum Job {
        case folder(Folder)
        case package(SpaceNode, ownBytes: Int64, device: Int32, parent: Folder, index: Int)
    }

    /// The worker pool for one scan: a LIFO stack of jobs (depth first, so memory stays small).
    final class Walk: @unchecked Sendable {
        let scanner: SpaceScanner
        let state: State
        private let condition = NSCondition()
        private var stack: [Job] = []
        private var finished = false
        private var rootOpened = false

        init(scanner: SpaceScanner, state: State) { self.scanner = scanner; self.state = state }

        /// Runs the walk to the end. false when the root couldn't be read.
        func run(root: Folder) -> Bool {
            push([.folder(root)])
            let group = DispatchGroup()
            for _ in 0..<scanner.threads {
                group.enter()
                let t = Thread { [self] in
                    work()
                    group.leave()
                }
                t.qualityOfService = .userInitiated
                t.stackSize = 4 << 20
                t.start()
            }
            group.wait()
            return rootOpened
        }

        private func push(_ jobs: [Job]) {
            guard !jobs.isEmpty else { return }
            condition.lock()
            stack.append(contentsOf: jobs.reversed())
            condition.broadcast()
            condition.unlock()
        }

        private func work() {
            while true {
                condition.lock()
                while stack.isEmpty && !finished { condition.wait() }
                if finished { condition.unlock(); return }
                let job = stack.removeLast()
                condition.unlock()
                switch job {
                case .folder(let f): read(f)
                case .package(let leaf, let own, let device, let parent, let index):
                    var claims: [(ItemIdentity, String, Int64)] = []
                    leaf.allocatedBytes = own + SpaceScanner.measureContents(leaf.path, device: device, claims: &claims, state: state)
                    for (identity, path, bytes) in claims { state.claim(identity, LinkClaim(path: path, bytes: bytes, holder: leaf)) }
                    state.tick(bytes: leaf.allocatedBytes, items: 1)
                    childDone(parent, index: index, opened: true)
                }
            }
        }

        private func read(_ f: Folder) {
            guard let entries = state.isCancelled() ? [] : BulkDirectory.read(f.node.path) else {
                guard let parent = f.parent else { return finish(opened: false) }
                return childDone(parent, index: f.index, opened: false)
            }
            var jobs: [Job] = []
            var fileBytes: Int64 = 0
            for e in entries {
                let path = f.node.path == "/" ? "/" + e.name : f.node.path + "/" + e.name
                f.items += 1
                if e.isDirectory {
                    // Another volume mounted here (/Volumes/…, /System/Volumes/…): not ours to count.
                    // A firmlink (/Users on the Data volume) changes device without being a mount point.
                    if e.identity.device != f.device && Volumes.isMountPoint(path) { continue }
                    let index = f.subjobs.count
                    if ClutterWalker.isPackage(e.name) {
                        let leaf = SpaceNode(name: e.name, path: path, kind: .package, identity: e.identity, allocatedBytes: 0)
                        f.subjobs.append(leaf)
                        jobs.append(.package(leaf, ownBytes: e.allocatedBytes, device: e.identity.device, parent: f, index: index))
                    } else {
                        let child = SpaceNode(name: e.name, path: path, kind: .folder, identity: e.identity, allocatedBytes: 0)
                        f.subjobs.append(child)
                        jobs.append(.folder(Folder(node: child, ownBytes: e.allocatedBytes, device: e.identity.device, parent: f, index: index)))
                    }
                    f.subjobBytes.append(e.allocatedBytes)
                } else {
                    let file = SpaceNode(name: e.name, path: path, kind: .file, identity: e.identity, allocatedBytes: e.allocatedBytes)
                    f.files.append(file)
                    fileBytes += e.allocatedBytes
                    if e.isRegularFile && e.linkCount > 1 { f.linked.append((file, e.identity)) }
                }
            }
            state.tick(bytes: fileBytes, items: f.files.count)
            f.opened = [Bool](repeating: false, count: jobs.count)
            f.pending = jobs.count
            if jobs.isEmpty { complete(f) } else { push(jobs) }
        }

        private func childDone(_ parent: Folder, index: Int, opened: Bool) {
            parent.lock.lock()
            parent.opened[index] = opened
            parent.pending -= 1
            let last = parent.pending == 0
            parent.lock.unlock()
            if last { complete(parent) }
        }

        /// All of `f`'s subjobs are done: build its children and report up.
        private func complete(_ f: Folder) {
            scanner.finish(f, state: state)
            if let parent = f.parent { childDone(parent, index: f.index, opened: true) } else { finish(opened: true) }
        }

        private func finish(opened: Bool) {
            condition.lock()
            rootOpened = opened
            finished = true
            condition.broadcast()
            condition.unlock()
        }
    }

    /// Builds a folder's children once its subfolders are measured: largest first, files past
    /// `filesPerFolder` lumped, unreadable subfolders in one block.
    func finish(_ f: Folder, state: State) {
        let node = f.node
        node.allocatedBytes = f.ownBytes
        var files = f.files
        var folders: [SpaceNode] = []
        var unreadable = 0
        var unreadableBytes: Int64 = 0
        var items = f.items
        for (i, child) in f.subjobs.enumerated() {
            if child.kind == .package {
                files.append(child)
            } else if f.opened[i] {
                child.parent = node
                folders.append(child)
                items += child.itemCount
            } else {
                unreadable += 1
                unreadableBytes += f.subjobBytes[i]
            }
        }
        files.sort { $0.allocatedBytes > $1.allocatedBytes }
        var kept = Array(files.prefix(filesPerFolder))
        let rest = files.dropFirst(filesPerFolder)
        var lump: SpaceNode?
        if !rest.isEmpty {
            let l = SpaceNode(name: "\(rest.count.formatted()) smaller files", path: node.path, kind: .smallFiles(count: rest.count),
                              identity: nil, allocatedBytes: rest.reduce(0) { $0 + $1.allocatedBytes })
            kept.append(l)
            lump = l
        }
        if !f.linked.isEmpty {
            let keptIDs = Set(kept.map { ObjectIdentifier($0) })
            for (file, identity) in f.linked {
                let holder = keptIDs.contains(ObjectIdentifier(file)) ? file : (lump ?? file)
                state.claim(identity, LinkClaim(path: file.path, bytes: file.allocatedBytes, holder: holder))
            }
        }
        for k in kept { k.parent = node }
        node.children = folders + kept
        node.allocatedBytes += node.children.reduce(0) { $0 + $1.allocatedBytes }
        node.itemCount = items
        if unreadable > 0 { addUnreadable(to: node, bytes: unreadableBytes, count: unreadable) }
        node.children.sort { $0.allocatedBytes > $1.allocatedBytes }
        // Free what the walk no longer needs (the tree keeps the nodes).
        f.files = []; f.linked = []; f.subjobs = []
    }

    /// Allocated bytes inside a package (not the package folder itself), one volume only.
    /// Hard-linked files are counted and reported in `claims`, to be settled after the walk.
    static func measureContents(_ path: String, device: Int32, claims: inout [(ItemIdentity, String, Int64)], state: State) -> Int64 {
        guard !state.isCancelled(), let entries = BulkDirectory.read(path) else { return 0 }
        var total: Int64 = 0
        for e in entries where e.identity.device == device {
            let child = path + "/" + e.name
            total += e.allocatedBytes
            if e.isDirectory {
                total += measureContents(child, device: device, claims: &claims, state: state)
            } else if e.isRegularFile && e.linkCount > 1 {
                claims.append((e.identity, child, e.allocatedBytes))
            }
        }
        return total
    }

    /// Every hard link was counted where it was found. Keep the bytes on the link with the first
    /// path and take them off the others (and every folder above them), so the totals match
    /// `du` whichever thread got there first.
    static func settleHardLinks(_ links: [ItemIdentity: [LinkClaim]]) {
        var touched: [ObjectIdentifier: SpaceNode] = [:]
        for (_, claims) in links where claims.count > 1 {
            for extra in claims.sorted(by: { $0.path < $1.path }).dropFirst() {
                var n: SpaceNode? = extra.holder
                while let node = n {
                    node.allocatedBytes -= extra.bytes
                    touched[ObjectIdentifier(node)] = node
                    n = node.parent
                }
            }
        }
        for node in touched.values { node.children.sort { $0.allocatedBytes > $1.allocatedBytes } }
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

    /// Can Disk Map offer a tick for this node? Items on the protected floor show none (§6.8).
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

/// Mounted volumes for the Disk Map picker.
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
