import Foundation

/// The slice of Homebrew's cask catalogue we keep (spec 013 §2): token, version, app names and
/// bundle IDs from `uninstall`/`zap` `quit` and `launchctl` entries.
public struct CaskEntry: Codable, Sendable, Equatable {
    public let token: String
    public let version: String
    public let appNames: [String]
    public let bundleIDs: [String]

    public init(token: String, version: String, appNames: [String], bundleIDs: [String]) {
        self.token = token; self.version = version; self.appNames = appNames; self.bundleIDs = bundleIDs
    }

    /// `short,build` → (short, build). Homebrew writes `latest` when it doesn't track versions.
    public var versions: (short: String, build: String?)? {
        guard version != "latest", !version.isEmpty else { return nil }
        let parts = version.split(separator: ",", maxSplits: 1).map(String.init)
        return (parts[0], parts.count > 1 ? parts[1] : nil)
    }
}

public struct CaskCatalog: Codable, Sendable {
    public static let url = "https://formulae.brew.sh/api/cask.json"
    /// Refreshed at most once a week (spec 013 §2).
    public static let maxAge: TimeInterval = 7 * 86_400

    public let fetched: Date
    public let entries: [CaskEntry]
    private var byBundleID: [String: Int] = [:]
    private var byAppName: [String: Int] = [:]

    enum CodingKeys: String, CodingKey { case fetched, entries }

    public init(fetched: Date, entries: [CaskEntry]) {
        self.fetched = fetched
        self.entries = entries
        index()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fetched = try c.decode(Date.self, forKey: .fetched)
        entries = try c.decode([CaskEntry].self, forKey: .entries)
        index()
    }

    private mutating func index() {
        for (i, e) in entries.enumerated() {
            for id in e.bundleIDs where byBundleID[id.lowercased()] == nil { byBundleID[id.lowercased()] = i }
            for n in e.appNames where byAppName[n.lowercased()] == nil { byAppName[n.lowercased()] = i }
        }
    }

    /// Matched by bundle ID, then by the app's file name (spec 013 §2 row 4).
    public func entry(bundleID: String, appFileName: String) -> CaskEntry? {
        if let i = byBundleID[bundleID.lowercased()] { return entries[i] }
        if let i = byAppName[appFileName.lowercased()] { return entries[i] }
        return nil
    }

    /// Reads Homebrew's full `cask.json` (a JSON array) and keeps only what we use.
    public static func parse(fullCatalogue data: Data, fetched: Date = Date()) throws -> CaskCatalog {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw Appcast.ParseError(description: "the Homebrew catalogue isn't a list")
        }
        var out: [CaskEntry] = []
        for cask in array {
            guard let token = cask["token"] as? String, let version = cask["version"] as? String else { continue }
            var apps: [String] = []
            for artifact in cask["artifacts"] as? [[String: Any]] ?? [] {
                guard let app = artifact["app"] as? [Any] else { continue }
                for a in app {
                    if let s = a as? String { apps.append(s) }
                    if let d = a as? [String: Any], let target = d["target"] as? String { apps.append((target as NSString).lastPathComponent) }
                }
            }
            var ids: [String] = []
            for artifact in cask["artifacts"] as? [[String: Any]] ?? [] {
                for key in ["uninstall", "zap"] {
                    for stanza in artifact[key] as? [[String: Any]] ?? [] {
                        for field in ["quit", "launchctl"] {
                            if let s = stanza[field] as? String { ids.append(s) }
                            if let list = stanza[field] as? [String] { ids += list }
                        }
                    }
                }
            }
            guard !apps.isEmpty else { continue }
            out.append(CaskEntry(token: token, version: version, appNames: apps, bundleIDs: ids.filter { $0.contains(".") }))
        }
        return CaskCatalog(fetched: fetched, entries: out)
    }
}
