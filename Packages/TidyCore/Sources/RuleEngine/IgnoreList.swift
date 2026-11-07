import Foundation
import SafetyFloor

/// John's ignore list (build spec §6.3). It can only narrow what rules find, never widen it.
public struct IgnoreList: Codable, Equatable, Sendable {
    public struct Entry: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Sendable { case path, ruleID }
        public let kind: Kind
        public let value: String
        public let added: String

        public init(kind: Kind, value: String, added: Date = Date()) {
            self.kind = kind
            self.value = value
            self.added = ISO8601DateFormatter.string(from: added, timeZone: .current, formatOptions: [.withFullDate])
        }
    }

    public var schemaVersion = 1
    public var entries: [Entry] = []

    public init(entries: [Entry] = []) { self.entries = entries }

    /// A path entry hides that item and everything inside it; a ruleID entry hides the whole rule.
    public func ignores(ruleID: String, path: String) -> Bool {
        entries.contains { e in
            switch e.kind {
            case .ruleID: e.value == ruleID
            case .path: PathNormalizer.normalize(e.value).map { PathNormalizer.isInside(path, $0) } ?? false
            }
        }
    }

    public func ignores(_ c: Candidate) -> Bool { ignores(ruleID: c.ruleID, path: c.path) }

    public mutating func add(_ entry: Entry) {
        guard !entries.contains(where: { $0.kind == entry.kind && $0.value == entry.value }) else { return }
        entries.append(entry)
    }

    public mutating func remove(_ entry: Entry) {
        entries.removeAll { $0.kind == entry.kind && $0.value == entry.value }
    }
}

/// Reads and writes `ignore.json` in TidyMyMac's support folder.
public struct IgnoreStore: Sendable {
    public let url: URL

    public init(home: Home) { url = home.tidySupport.appendingPathComponent("ignore.json") }

    public func load() throws -> IgnoreList {
        guard let data = FileManager.default.contents(atPath: url.path) else { return IgnoreList() }
        return try JSONDecoder().decode(IgnoreList.self, from: data)
    }

    public func save(_ list: IgnoreList) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try e.encode(list).write(to: url, options: .atomic)
    }
}
