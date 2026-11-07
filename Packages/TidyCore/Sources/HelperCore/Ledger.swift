import Foundation
import HelperProtocol
import SafetyFloor

/// Every item the helper moved into a user's Trash (005 §8). Root-owned, mode 644. Entries whose
/// Trash item has gone are dropped on each read.
public struct Ledger: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func entries() -> [LedgerEntry] {
        guard let data = FileManager.default.contents(atPath: url.path),
              let all = try? HelperCoding.decode([LedgerEntry].self, data) else { return [] }
        return all.filter { FileStatus.lstat($0.trashPath) != nil }
    }

    public func save(_ entries: [LedgerEntry]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try HelperCoding.encode(entries).write(to: url, options: .atomic)
        chmod(url.path, 0o644)
    }

    public func append(_ entry: LedgerEntry) throws {
        try save(entries() + [entry])
    }

    public func remove(_ ids: Set<UUID>) throws {
        try save(entries().filter { !ids.contains($0.id) })
    }
}
