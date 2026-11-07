import Foundation
import SafetyFloor

/// Loads rule files from a folder URL (spec 016 §3): the app passes its bundled `Rules/`,
/// tests pass the repo's `Rules/`. Unknown fields are load errors (spec 006 §2).
public enum RuleLoader {
    public struct LoadError: Error, CustomStringConvertible, Equatable {
        public let file: String
        public let message: String
        public var description: String { "\(file): \(message)" }
    }

    /// Which kind of rule a file holds is decided by its name.
    public enum FileKind: Equatable {
        case clean, leftoverLocations, protect, appOverrides, schema
        public init(fileName: String) {
            switch fileName {
            case "leftover-locations.json": self = .leftoverLocations
            case "protected.json": self = .protect
            case "app-overrides.json": self = .appOverrides
            case "schema.json": self = .schema
            default: self = .clean
            }
        }
    }

    public static func load(from folder: URL, version: Int) throws -> RuleSet {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var set = RuleSet(version: version)
        for url in files {
            try loadFile(url, into: &set)
        }
        return set
    }

    public static func loadFile(_ url: URL, into set: inout RuleSet) throws {
        let name = url.lastPathComponent
        let kind = FileKind(fileName: name)
        if kind == .schema { return }
        let data = try Data(contentsOf: url)
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) } catch {
            throw LoadError(file: name, message: "not valid JSON (\(error.localizedDescription))")
        }
        guard let top = object as? [String: Any] else { throw LoadError(file: name, message: "top level must be an object") }
        try checkKeys(top, allowed: ["schemaVersion", "rules"], at: "top level", file: name)
        guard top["schemaVersion"] as? Int == 1 else { throw LoadError(file: name, message: "schemaVersion must be 1") }
        guard let rules = top["rules"] as? [[String: Any]] else { throw LoadError(file: name, message: "'rules' must be a list of objects") }
        for (i, rule) in rules.enumerated() {
            try checkRuleKeys(rule, kind: kind, at: "rules[\(i)]", file: name)
        }

        let decoder = JSONDecoder()
        func decode<T: Decodable>(_ type: T.Type) throws -> [T] {
            do { return try decoder.decode(FileBody<T>.self, from: data).rules } catch {
                throw LoadError(file: name, message: describe(error))
            }
        }
        switch kind {
        case .clean:
            for r in try decode(CleanRule.self) { set.cleanRules.append(r); set.fileOfID[r.id] = set.fileOfID[r.id] ?? name }
        case .leftoverLocations:
            for r in try decode(LeftoverLocation.self) { set.leftoverLocations.append(r); set.fileOfID[r.id] = set.fileOfID[r.id] ?? name }
        case .protect:
            for r in try decode(ProtectRule.self) { set.protectRules.append(r); set.fileOfID[r.id] = set.fileOfID[r.id] ?? name }
        case .appOverrides:
            for r in try decode(AppOverride.self) { set.appOverrides.append(r); set.fileOfID[r.id] = set.fileOfID[r.id] ?? name }
        case .schema: break
        }
    }

    private struct FileBody<T: Decodable>: Decodable {
        let schemaVersion: Int
        let rules: [T]
    }

    static func keys<K: CodingKey & CaseIterable>(_ k: K.Type) -> Set<String> { Set(K.allCases.map(\.stringValue)) }

    static func checkRuleKeys(_ rule: [String: Any], kind: FileKind, at path: String, file: String) throws {
        switch kind {
        case .clean:
            try checkKeys(rule, allowed: keys(CleanRule.CodingKeys.self), at: path, file: file)
            for (i, t) in (rule["targets"] as? [[String: Any]] ?? []).enumerated() {
                try checkKeys(t, allowed: keys(RuleTarget.CodingKeys.self), at: "\(path).targets[\(i)]", file: file)
            }
            if let c = rule["conditions"] as? [String: Any] { try checkKeys(c, allowed: keys(RuleConditions.CodingKeys.self), at: "\(path).conditions", file: file) }
            if let g = rule["guards"] as? [String: Any] { try checkKeys(g, allowed: keys(RuleGuards.CodingKeys.self), at: "\(path).guards", file: file) }
            if let m = rule["macOS"] as? [String: Any] { try checkKeys(m, allowed: keys(MacOSRange.CodingKeys.self), at: "\(path).macOS", file: file) }
        case .leftoverLocations:
            try checkKeys(rule, allowed: keys(LeftoverLocation.CodingKeys.self), at: path, file: file)
        case .protect:
            try checkKeys(rule, allowed: keys(ProtectRule.CodingKeys.self), at: path, file: file)
        case .appOverrides:
            try checkKeys(rule, allowed: keys(AppOverride.CodingKeys.self), at: path, file: file)
        case .schema: return
        }
        if let s = rule["source"] as? [String: Any] { try checkKeys(s, allowed: keys(RuleSource.CodingKeys.self), at: "\(path).source", file: file) }
    }

    static func checkKeys(_ object: [String: Any], allowed: Set<String>, at path: String, file: String) throws {
        if let unknown = object.keys.sorted().first(where: { !allowed.contains($0) }) {
            let id = object["id"] as? String ?? object["bundleId"] as? String
            throw LoadError(file: file, message: "unknown field '\(unknown)' in \(id.map { "rule \($0)" } ?? path)")
        }
    }

    static func describe(_ error: Error) -> String {
        guard let e = error as? DecodingError else { return "\(error)" }
        func path(_ c: [CodingKey]) -> String { c.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined() }
        switch e {
        case .keyNotFound(let k, let ctx): return "missing field '\(k.stringValue)' at \(path(ctx.codingPath))"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx), .dataCorrupted(let ctx):
            return "bad value at \(path(ctx.codingPath)): \(ctx.debugDescription)"
        @unknown default: return "\(e)"
        }
    }
}

extension RuleSet {
    /// Floor additions from `protected.json` (spec 006 §5): they only ever add.
    public func floorAdditions(home: Home) -> [FloorEntry] {
        protectRules.compactMap { rule in
            guard let root = home.expand(rule.root) else { return nil }
            switch rule.match {
            case .self: return FloorEntry(path: root, reason: rule.reason)
            case .children: return FloorEntry(path: root + "/*", reason: rule.reason)
            case .glob:
                guard let p = rule.pattern else { return nil }
                return FloorEntry(path: root + "/" + p, reason: rule.reason)
            }
        }
    }
}
