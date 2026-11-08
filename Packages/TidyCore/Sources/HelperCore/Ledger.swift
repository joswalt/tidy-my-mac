import Darwin
import Foundation
import HelperProtocol
import SafetyFloor

/// Every item the helper moved into a user's Trash (005 §8). Root-owned, mode 600. Entries whose
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
        // Created 0600 from the start (never briefly world-readable), then renamed into place.
        let data = HelperCoding.encode(entries)
        let tmp = url.path + ".tmp-\(UUID().uuidString)"
        let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        _ = fchmod(fd, 0o600)
        let written = data.withUnsafeBytes { buf in buf.isEmpty ? 0 : write(fd, buf.baseAddress, buf.count) }
        let synced = fsync(fd) == 0
        close(fd)
        guard written == data.count, synced, rename(tmp, url.path) == 0 else {
            unlink(tmp)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    public func append(_ entry: LedgerEntry) throws {
        try save(entries() + [entry])
    }

    public func remove(_ ids: Set<UUID>) throws {
        try save(entries().filter { !ids.contains($0.id) })
    }
}
