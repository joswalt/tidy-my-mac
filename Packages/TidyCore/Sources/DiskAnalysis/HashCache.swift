import Foundation
import SafetyFloor
import SQLite3

/// Hash cache for the duplicate finder (spec 014 §7): SQLite through the system `libsqlite3`,
/// keyed on path + size + modification date + inode. A changed file gets a fresh entry.
public final class HashCache: @unchecked Sendable {
    public struct Key: Sendable, Hashable {
        public let path: String
        public let size: Int64
        public let modified: Date
        public let inode: UInt64

        public init(path: String, size: Int64, modified: Date, inode: UInt64) {
            self.path = path
            self.size = size
            self.modified = modified
            self.inode = inode
        }
    }

    public struct Hashes: Sendable, Equatable {
        public var partial: Data?
        public var full: Data?
    }

    public let url: URL
    private var db: OpaquePointer?
    private let lock = NSLock()

    /// `~/Library/Application Support/TidyMyMac/Cache/hashes.sqlite`.
    public static func defaultURL(home: Home) -> URL {
        home.tidySupport.appendingPathComponent("Cache", isDirectory: true).appendingPathComponent("hashes.sqlite")
    }

    public struct OpenError: Error, CustomStringConvertible {
        public let description: String
    }

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            db = nil
            throw OpenError(description: "Couldn't open the hash cache: \(message)")
        }
        try exec("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS hashes (
              path TEXT PRIMARY KEY, size INTEGER NOT NULL, mtime REAL NOT NULL, inode INTEGER NOT NULL,
              partial BLOB, full BLOB);
            """)
    }

    deinit { sqlite3_close(db) }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let message = err.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(err)
            throw OpenError(description: message)
        }
    }

    /// The cached hashes, or nil when there are none or the file changed since.
    public func lookup(_ key: Key) -> Hashes? {
        lock.withLock {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT size, mtime, inode, partial, full FROM hashes WHERE path = ?", -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, key.path, -1, Self.transient)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            guard sqlite3_column_int64(stmt, 0) == key.size,
                  sqlite3_column_double(stmt, 1) == key.modified.timeIntervalSince1970,
                  UInt64(bitPattern: sqlite3_column_int64(stmt, 2)) == key.inode else { return nil }
            return Hashes(partial: Self.blob(stmt, 3), full: Self.blob(stmt, 4))
        }
    }

    /// Stores (or replaces) the hashes for a file; a nil hash keeps what is cached for the same key.
    public func store(_ key: Key, partial: Data?, full: Data?) {
        let existing = lookup(key)
        let p = partial ?? existing?.partial, f = full ?? existing?.full
        lock.withLock {
            var stmt: OpaquePointer?
            let sql = "INSERT OR REPLACE INTO hashes (path, size, mtime, inode, partial, full) VALUES (?, ?, ?, ?, ?, ?)"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, key.path, -1, Self.transient)
            sqlite3_bind_int64(stmt, 2, key.size)
            sqlite3_bind_double(stmt, 3, key.modified.timeIntervalSince1970)
            sqlite3_bind_int64(stmt, 4, Int64(bitPattern: key.inode))
            Self.bind(stmt, 5, p)
            Self.bind(stmt, 6, f)
            _ = sqlite3_step(stmt)
        }
    }

    /// Settings › Cleanup › Clear Hash Cache. Empties the table; the file stays (it is ours, on the floor).
    public func clear() throws {
        try lock.withLock { try exec("DELETE FROM hashes; VACUUM;") }
    }

    public var count: Int {
        lock.withLock {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM hashes", -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
        }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func blob(_ stmt: OpaquePointer?, _ col: Int32) -> Data? {
        guard sqlite3_column_type(stmt, col) == SQLITE_BLOB, let p = sqlite3_column_blob(stmt, col) else { return nil }
        return Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, col)))
    }

    private static func bind(_ stmt: OpaquePointer?, _ col: Int32, _ data: Data?) {
        guard let data else { sqlite3_bind_null(stmt, col); return }
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, col, $0.baseAddress, Int32(data.count), transient) }
    }
}
