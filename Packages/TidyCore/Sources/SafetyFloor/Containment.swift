import Foundation

public enum ContainmentError: Error, Equatable, Sendable, CustomStringConvertible {
    case notAbsolute
    case dotDot
    case equalsRoot
    case notInsideRoot
    case rootMissing
    case missing
    case symlinkedParent(String)
    case symlinkedItem
    case otherVolume

    public var description: String {
        switch self {
        case .notAbsolute: "the path is not absolute"
        case .dotDot: "the path contains '..'"
        case .equalsRoot: "the item is the rule's root folder itself"
        case .notInsideRoot: "the item is not inside the rule's root folder"
        case .rootMissing: "the rule's root folder is missing"
        case .missing: "the item no longer exists"
        case .symlinkedParent(let p): "a parent folder (\(p)) is a symbolic link"
        case .symlinkedItem: "the item is a symbolic link"
        case .otherVolume: "the item is on another volume"
        }
    }
}

/// Path containment (spec 006 §5.3): the item must sit strictly inside the root, reached without
/// following any symlink, on the root's volume. `root` should be a real path (no symlinks).
public enum Containment {
    @discardableResult
    public static func validate(item: String, root: String) throws(ContainmentError) -> FileStatus {
        guard item.hasPrefix("/"), root.hasPrefix("/") else { throw .notAbsolute }
        if item.split(separator: "/").contains("..") { throw .dotDot }
        guard let nItem = PathNormalizer.normalize(item), let nRoot = PathNormalizer.normalize(root) else { throw .dotDot }
        let itemComps = PathNormalizer.components(nItem), rootComps = PathNormalizer.components(nRoot)
        let fi = itemComps.map(PathNormalizer.fold), fr = rootComps.map(PathNormalizer.fold)
        guard fi.count >= fr.count, Array(fi.prefix(fr.count)) == fr else { throw .notInsideRoot }
        if fi.count == fr.count { throw .equalsRoot }

        guard let rootStatus = FileStatus.lstat(root), rootStatus.isDirectory else { throw .rootMissing }
        // Walk down from the root using the item's own spelling, never following links.
        var current = root.hasSuffix("/") ? String(root.dropLast()) : root
        for (index, name) in itemComps.dropFirst(rootComps.count).enumerated() {
            current += "/" + name
            guard let st = FileStatus.lstat(current) else { throw .missing }
            let isLast = index == itemComps.count - rootComps.count - 1
            if st.isSymlink { throw isLast ? .symlinkedItem : .symlinkedParent(current) }
            if st.device != rootStatus.device { throw .otherVolume }
            if isLast { return st }
            if !st.isDirectory { throw .notInsideRoot }
        }
        throw .missing
    }
}
