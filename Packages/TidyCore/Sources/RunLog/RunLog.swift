import Foundation

// Run log (build spec §6.1): one JSON Lines file per run, a header line, one item line per
// item written as it happens, and a summary line. A run without a summary was interrupted.

/// Namespace marker for the RunLog library.
public enum RunLog {
    public static let moduleName = "RunLog"
}

public enum RunAction: Codable, Hashable, Sendable, CustomStringConvertible {
    case trash
    case delete
    case operation(String)

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        switch s {
        case "trash": self = .trash
        case "delete": self = .delete
        default: self = .operation(s)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    public var description: String {
        switch self {
        case .trash: "trash"
        case .delete: "delete"
        case .operation(let id): id
        }
    }
}

public enum RunResult: String, Codable, Sendable {
    case done, skipped, failed
}

public struct RunHeader: Codable, Equatable, Sendable {
    public var type = "header"
    public let runID: UUID
    public let start: Date
    public let module: String
    public let appVersion: String
    public let ruleSetVersion: Int
    public let dryRun: Bool

    public init(runID: UUID = UUID(), start: Date = Date(), module: String, appVersion: String, ruleSetVersion: Int, dryRun: Bool) {
        self.runID = runID
        self.start = start
        self.module = module
        self.appVersion = appVersion
        self.ruleSetVersion = ruleSetVersion
        self.dryRun = dryRun
    }
}

public struct RunItem: Codable, Equatable, Sendable {
    public var type = "item"
    public let time: Date
    /// The rule id, or `manual` for hand-picked items.
    public let ruleID: String
    public let path: String
    public let allocatedBytes: Int64
    public let action: RunAction
    public let result: RunResult
    public let reason: String?
    public let trashPath: String?
    public let helperLedgerID: String?

    public init(time: Date = Date(), ruleID: String, path: String, allocatedBytes: Int64, action: RunAction,
                result: RunResult, reason: String? = nil, trashPath: String? = nil, helperLedgerID: String? = nil) {
        self.time = time
        self.ruleID = ruleID
        self.path = path
        self.allocatedBytes = allocatedBytes
        self.action = action
        self.result = result
        self.reason = reason
        self.trashPath = trashPath
        self.helperLedgerID = helperLedgerID
    }
}

public struct RunTotals: Codable, Equatable, Sendable {
    public var count: Int = 0
    public var bytes: Int64 = 0
}

public struct RunSummary: Codable, Equatable, Sendable {
    public var type = "summary"
    public let end: Date
    /// Done items per action (`trash`, `delete` or an operation id).
    public let done: [String: RunTotals]
    public let skipped: RunTotals
    public let failed: RunTotals
}

/// Appends one run's lines to its own file. Each line is flushed to disk as it is written,
/// so a crash leaves every finished line readable.
public final class RunLogWriter: @unchecked Sendable {
    public let header: RunHeader
    public let fileURL: URL
    private let handle: FileHandle
    private let lock = NSLock()
    private var done: [String: RunTotals] = [:]
    private var skipped = RunTotals()
    private var failed = RunTotals()
    private var finished = false

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    /// File name `<yyyy-MM-dd'T'HHmmss>-<runID>.jsonl` in `directory` (created if needed).
    public init(directory: URL, header: RunHeader) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HHmmss"
        let name = "\(f.string(from: header.start))-\(header.runID.uuidString).jsonl"
        fileURL = directory.appendingPathComponent(name)
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: fileURL.path])
        }
        handle = try FileHandle(forWritingTo: fileURL)
        self.header = header
        try writeLine(header)
    }

    public func append(_ item: RunItem) throws {
        try lock.withLock {
            precondition(!finished, "run log already finished")
            switch item.result {
            case .done:
                done[item.action.description, default: RunTotals()].count += 1
                done[item.action.description, default: RunTotals()].bytes += item.allocatedBytes
            case .skipped: skipped.count += 1; skipped.bytes += item.allocatedBytes
            case .failed: failed.count += 1; failed.bytes += item.allocatedBytes
            }
            try writeLine(item)
        }
    }

    @discardableResult
    public func finish(end: Date = Date()) throws -> RunSummary {
        try lock.withLock {
            let summary = RunSummary(end: end, done: done, skipped: skipped, failed: failed)
            try writeLine(summary)
            try handle.close()
            finished = true
            return summary
        }
    }

    private func writeLine<T: Encodable>(_ value: T) throws {
        var data = try Self.encoder.encode(value)
        data.append(0x0A)
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }
}

/// A run read back from disk.
public struct RunRecord: Equatable, Sendable {
    public let header: RunHeader
    public let items: [RunItem]
    public let summary: RunSummary?
    /// No summary line: the app stopped mid-run ("Interrupted" in Health).
    public var isInterrupted: Bool { summary == nil }
}

public enum RunLogReader {
    public enum ReadError: Error { case noHeader }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private struct LineType: Decodable { let type: String }

    /// Reads one run file. Lines that don't parse (a truncated last line after a crash) are ignored.
    public static func read(_ url: URL) throws -> RunRecord {
        let data = try Data(contentsOf: url)
        var header: RunHeader?
        var items: [RunItem] = []
        var summary: RunSummary?
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            let d = Data(line)
            guard let t = try? decoder.decode(LineType.self, from: d) else { continue }
            switch t.type {
            case "header": header = try? decoder.decode(RunHeader.self, from: d)
            case "item": if let i = try? decoder.decode(RunItem.self, from: d) { items.append(i) }
            case "summary": summary = try? decoder.decode(RunSummary.self, from: d)
            default: continue
            }
        }
        guard let header else { throw ReadError.noHeader }
        return RunRecord(header: header, items: items, summary: summary)
    }

    /// All runs in `directory`, newest first; unreadable files are skipped.
    public static func runs(in directory: URL, limit: Int = .max) -> [RunRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(limit)
            .compactMap { try? read($0) }
    }
}
