import Darwin
import Foundation
import SafetyFloor

/// One file (or one package, measured as a whole) found by `ClutterWalker`.
public struct FileEntry: Sendable, Hashable, Identifiable {
    public let path: String
    /// The scope folder it was found under (the containment root when it is removed).
    public let root: String
    public let identity: ItemIdentity
    /// A package or bundle measured as one unit (an `.app`, a `.pages` document, …).
    public let isPackage: Bool
    /// Logical length in bytes (what duplicates compare). For a package, its allocated size.
    public let size: Int64
    public let allocatedBytes: Int64
    public let modified: Date
    public let created: Date

    public init(path: String, root: String, identity: ItemIdentity, isPackage: Bool, size: Int64, allocatedBytes: Int64,
                modified: Date, created: Date) {
        self.path = path
        self.root = root
        self.identity = identity
        self.isPackage = isPackage
        self.size = size
        self.allocatedBytes = allocatedBytes
        self.modified = modified
        self.created = created
    }

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var folder: String { (path as NSString).deletingLastPathComponent }
}

/// Where My Clutter looks (spec 014 §3) and the smallest file it cares about (§4).
public struct ClutterScope: Sendable, Equatable {
    public var folders: [String]
    public var minimumSize: Int64

    public static let defaultMinimumSize: Int64 = 1_048_576

    public init(folders: [String], minimumSize: Int64 = ClutterScope.defaultMinimumSize) {
        self.folders = folders
        self.minimumSize = minimumSize
    }

    /// Desktop, Documents, Downloads, Pictures, Movies and Music. External volumes only when added.
    public static func defaultFolders(_ home: Home) -> [String] {
        [home.desktop, home.documents, home.downloads, home.pictures, home.movies, home.music].map(\.path)
    }

    public static func defaults(_ home: Home, minimumSize: Int64 = ClutterScope.defaultMinimumSize) -> ClutterScope {
        ClutterScope(folders: defaultFolders(home), minimumSize: minimumSize)
    }
}

/// Walks the My Clutter scope with the duplicate finder's skips (spec 014 §4): never `~/Library`
/// (so never iCloud Drive or `~/Library/CloudStorage`), never hidden items, `.git` or `node_modules`, packages as
/// opaque units, iCloud placeholders never read, nothing on the protected floor, no symlinks
/// followed, no other volume entered. Hard links are returned once.
public struct ClutterWalker: Sendable {
    public let home: Home
    public let floor: ProtectedFloor

    public init(home: Home, floor: ProtectedFloor? = nil) {
        self.home = home
        self.floor = floor ?? ProtectedFloor(home: home)
    }

    /// Every regular file of at least `minimumSize` (default: the scope's), and with
    /// `includePackages` every package as one item. Duplicates pass `includePackages: false`.
    public func files(_ scope: ClutterScope, includePackages: Bool, minimumSize: Int64? = nil,
                      isCancelled: @Sendable () -> Bool = { false }) -> [FileEntry] {
        let minimum = minimumSize ?? scope.minimumSize
        var state = WalkState()
        var out: [FileEntry] = []
        for folder in scope.folders {
            guard let root = PathNormalizer.realPath(folder), let st = FileStatus.lstat(root), st.isDirectory else { continue }
            if skipsFolder(root) { continue }
            walk(root, root: root, device: st.device, minimum: minimum, includePackages: includePackages,
                 state: &state, out: &out, isCancelled: isCancelled)
        }
        return out
    }

    struct WalkState {
        var seen: Set<ItemIdentity> = []
        var seenFolders: Set<ItemIdentity> = []
    }

    /// `~/Library` and everything in it, which covers iCloud Drive and cloud storage folders.
    func skipsFolder(_ path: String) -> Bool {
        PathNormalizer.isInside(path, PathNormalizer.realPath(home.library.path) ?? home.library.path)
    }

    /// Folders other tools manage: removing a copy inside one breaks the project it belongs to.
    /// `node_modules` is skipped as well as `.git` (a narrowing of spec 014 §4, flagged for John).
    static let skippedFolderNames: Set<String> = [".git", "node_modules"]

    static func isHidden(_ name: String, _ st: FileStatus) -> Bool {
        name.hasPrefix(".") || st.flags & UInt32(UF_HIDDEN) != 0
    }

    static func isPackage(_ name: String) -> Bool {
        let ext = PathNormalizer.fold((name as NSString).pathExtension)
        return !ext.isEmpty && ProtectedFloor.packageExtensions.contains(ext)
    }

    private func walk(_ dir: String, root: String, device: Int32, minimum: Int64, includePackages: Bool,
                      state: inout WalkState, out: inout [FileEntry], isCancelled: @Sendable () -> Bool) {
        guard let dst = FileStatus.lstat(dir), state.seenFolders.insert(dst.identity).inserted else { return }
        for name in DirectoryReader.names(dir) {
            if isCancelled() { return }
            let path = dir + "/" + name
            guard let st = FileStatus.lstat(path), !st.isSymlink, !Self.isHidden(name, st) else { continue }
            if st.device != device { continue }
            if st.isDirectory {
                if Self.skippedFolderNames.contains(name) || skipsFolder(path) { continue }
                if Self.isPackage(name) {
                    guard includePackages, state.seen.insert(st.identity).inserted else { continue }
                    let bytes = TreeMeasure.allocatedBytes(path, device: device, seen: &state.seen)
                    guard bytes >= minimum, !floor.verdict(for: path, context: .manualPick).isProtected else { continue }
                    out.append(FileEntry(path: path, root: root, identity: st.identity, isPackage: true, size: bytes,
                                         allocatedBytes: bytes, modified: st.modified, created: Self.created(path) ?? st.modified))
                    continue
                }
                walk(path, root: root, device: device, minimum: minimum, includePackages: includePackages,
                     state: &state, out: &out, isCancelled: isCancelled)
            } else if st.isRegularFile {
                guard st.size >= minimum, !st.isDataless, state.seen.insert(st.identity).inserted else { continue }
                if floor.verdict(for: path, context: .manualPick).isProtected { continue }
                out.append(FileEntry(path: path, root: root, identity: st.identity, isPackage: false, size: st.size,
                                     allocatedBytes: st.allocatedBytes, modified: st.modified, created: Self.created(path) ?? st.modified))
            }
        }
    }

    /// Creation (birth) date, without following links.
    static func created(_ path: String) -> Date? {
        var st = stat()
        guard Darwin.lstat(path, &st) == 0 else { return nil }
        let t = st.st_birthtimespec
        return Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_nsec) / 1e9)
    }
}

/// Reads a folder's entry names with `readdir` (no sorting, no stat).
enum DirectoryReader {
    /// nil when the folder can't be opened (permissions, gone).
    static func open(_ path: String) -> [String]? {
        guard let d = opendir(path) else { return nil }
        defer { closedir(d) }
        var names: [String] = []
        while let entry = readdir(d) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if name != "." && name != ".." { names.append(name) }
        }
        return names
    }

    static func names(_ path: String) -> [String] { open(path) ?? [] }
}

/// Allocated size of a whole tree (a package or folder), hard links once, one volume only.
enum TreeMeasure {
    static func allocatedBytes(_ path: String, device: Int32, seen: inout Set<ItemIdentity>) -> Int64 {
        guard let st = FileStatus.lstat(path), st.device == device else { return 0 }
        if st.isRegularFile && st.linkCount > 1 && !seen.insert(st.identity).inserted { return 0 }
        var total = st.allocatedBytes
        if st.isDirectory {
            for name in DirectoryReader.names(path) {
                total += allocatedBytes(path + "/" + name, device: device, seen: &seen)
            }
        }
        return total
    }
}
