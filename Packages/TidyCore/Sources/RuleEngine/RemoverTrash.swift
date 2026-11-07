import Foundation
import SafetyFloor

/// The real Trash, through Finder's mechanism (keeps Put Back working).
public struct SystemTrash: TrashMover {
    public init() {}

    public func moveToTrash(_ path: String) throws -> String {
        try TestFence.check(path)
        var result: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &result)
        return (result as URL?)?.path ?? ""
    }
}

/// A Trash folder inside a given home (fixture homes in tests). Uses rename(2), so the item
/// keeps its inode and the test can prove it is the same item.
public struct HomeTrash: TrashMover {
    public let home: Home

    public init(home: Home) { self.home = home }

    public func moveToTrash(_ path: String) throws -> String {
        try TestFence.check(path)
        let trash = home.trash.path
        try FileManager.default.createDirectory(atPath: trash, withIntermediateDirectories: true)
        let name = (path as NSString).lastPathComponent
        var dest = trash + "/" + name
        var n = 2
        while FileStatus.lstat(dest) != nil {
            let ns = name as NSString
            let ext = ns.pathExtension
            dest = trash + "/" + ns.deletingPathExtension + " \(n)" + (ext.isEmpty ? "" : "." + ext)
            n += 1
        }
        if Darwin.rename(path, dest) != 0 {
            throw Remover.RemoveError(path: path, message: String(cString: strerror(errno)))
        }
        return dest
    }
}
