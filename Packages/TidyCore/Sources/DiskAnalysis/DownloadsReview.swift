import Darwin
import Foundation
import SafetyFloor

/// One top-level item of `~/Downloads` (build spec §6.7).
public struct DownloadItem: Sendable, Hashable, Identifiable {
    public let path: String
    public let root: String
    public let identity: ItemIdentity
    public let isDirectory: Bool
    public let allocatedBytes: Int64
    public let modified: Date
    /// When it arrived in Downloads (falls back to the modification date).
    public let dateAdded: Date
    /// Host of the page it was downloaded from (`kMDItemWhereFroms`), host only.
    public let sourceHost: String?
    /// Copies elsewhere with the same full hash (spec 014 §8). Never from names alone.
    public var alsoElsewhere: [String] = []

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
}

public enum DownloadsReview {
    /// Default filter: older than 30 days.
    public static let defaultOlderThanDays = 30

    /// Top-level items of `~/Downloads`, hidden ones and floor items left out, sizes allocated.
    public static func items(home: Home, floor: ProtectedFloor? = nil) -> [DownloadItem] {
        let floor = floor ?? ProtectedFloor(home: home)
        guard let root = PathNormalizer.realPath(home.downloads.path), let rst = FileStatus.lstat(root), rst.isDirectory else { return [] }
        var seen: Set<ItemIdentity> = []
        var out: [DownloadItem] = []
        for name in DirectoryReader.names(root).sorted() {
            let path = root + "/" + name
            guard let st = FileStatus.lstat(path), !st.isSymlink, !ClutterWalker.isHidden(name, st), st.device == rst.device else { continue }
            if floor.verdict(for: path, context: .manualPick).isProtected { continue }
            let bytes = st.isDirectory ? TreeMeasure.allocatedBytes(path, device: rst.device, seen: &seen) : st.allocatedBytes
            out.append(DownloadItem(path: path, root: root, identity: st.identity, isDirectory: st.isDirectory, allocatedBytes: bytes,
                                    modified: st.modified, dateAdded: dateAdded(path) ?? st.modified, sourceHost: sourceHost(path)))
        }
        return out
    }

    public static func dateAdded(_ path: String) -> Date? {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate
    }

    /// The host of the first URL in `com.apple.metadata:kMDItemWhereFroms`.
    public static func sourceHost(_ path: String) -> String? {
        let name = "com.apple.metadata:kMDItemWhereFroms"
        let len = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard getxattr(path, name, &buf, len, 0, XATTR_NOFOLLOW) == len,
              let list = try? PropertyListSerialization.propertyList(from: Data(buf), format: nil) as? [String] else { return nil }
        for s in list { if let host = URL(string: s)?.host(), !host.isEmpty { return host } }
        return nil
    }

    /// Flags items with a real hash match outside Downloads.
    public static func markDuplicates(_ items: [DownloadItem], groups: [DuplicateGroup], downloads: String) -> [DownloadItem] {
        var others: [String: [String]] = [:]
        for g in groups {
            let outside = g.files.map(\.path).filter { !PathNormalizer.isInside($0, downloads) }
            guard !outside.isEmpty else { continue }
            for f in g.files where PathNormalizer.isInside(f.path, downloads) { others[f.path] = outside }
        }
        return items.map { item in
            var item = item
            item.alsoElsewhere = others[item.path] ?? []
            return item
        }
    }

    public static func isOld(_ item: DownloadItem, days: Int, now: Date = Date()) -> Bool {
        item.dateAdded < now.addingTimeInterval(-Double(days) * 86_400)
    }
}
