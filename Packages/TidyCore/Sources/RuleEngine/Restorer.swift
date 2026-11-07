import Darwin
import Foundation
import RunLog
import SafetyFloor

/// Puts back items the app itself moved to the Trash (build spec §6.2).
public struct Restorer: Sendable {
    public enum Result: Equatable, Sendable, CustomStringConvertible {
        case restored
        case notTrashed
        case notInTrash
        case originalTaken
        case parentMissing
        case needsHelper
        case failed(String)

        public var description: String {
            switch self {
            case .restored: "Restored."
            case .notTrashed: "This item was deleted permanently, so it can't be restored."
            case .notInTrash: "It is no longer in the Trash."
            case .originalTaken: "Something else is now at its original location."
            case .parentMissing: "The folder it came from no longer exists."
            case .needsHelper: "Items removed with administrator rights are restored by the helper (coming in a later build)."
            case .failed(let why): "Couldn't restore it: \(why)."
            }
        }
    }

    public let home: Home

    public init(home: Home) { self.home = home }

    /// What restoring would do, without doing it.
    public func check(_ item: RunItem) -> Result {
        guard item.result == .done, item.action == .trash, let trashPath = item.trashPath, !trashPath.isEmpty else { return .notTrashed }
        if item.helperLedgerID != nil { return .needsHelper }
        guard isTrashLocation(trashPath), FileStatus.lstat(trashPath) != nil else { return .notInTrash }
        if FileStatus.lstat(item.path) != nil { return .originalTaken }
        let parent = (item.path as NSString).deletingLastPathComponent
        guard FileStatus.lstat(parent)?.isDirectory == true else { return .parentMissing }
        return .restored
    }

    public func restore(_ item: RunItem) -> Result {
        let ready = check(item)
        guard ready == .restored, let trashPath = item.trashPath else { return ready }
        do {
            try TestFence.check(trashPath)
            try TestFence.check(item.path)
        } catch {
            return .failed("\(error)")
        }
        if Darwin.rename(trashPath, item.path) != 0 { return .failed(String(cString: strerror(errno))) }
        return .restored
    }

    /// Only the user's Trash or a volume's per-user Trash, never an arbitrary path from a log file.
    func isTrashLocation(_ path: String) -> Bool {
        guard let n = PathNormalizer.normalize(path) else { return false }
        if PathNormalizer.isInside(n, home.trash.path), PathNormalizer.fold(n) != PathNormalizer.fold(home.trash.path) { return true }
        let c = PathNormalizer.components(n)
        return c.count > 4 && c[0] == "Volumes" && c[2] == ".Trashes" && c[3] == String(home.userID)
    }
}
