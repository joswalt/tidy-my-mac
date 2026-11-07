import Foundation

/// Why something is being removed. Hand-picked items (Large & Old, duplicates, Space Lens)
/// may come from inside the personal folders; rule-found items may not (spec 006 §5).
public enum RemovalContext: Sendable {
    case rule
    case manualPick
}

public enum FloorVerdict: Equatable, Sendable {
    case allowed
    case protected(String)

    public var isProtected: Bool { if case .protected = self { true } else { false } }
}

/// One protected place: a sequence of path-component patterns (literal names or globs).
public struct FloorEntry: Sendable, Hashable {
    public enum Scope: Sendable, Hashable {
        /// The item and everything inside it.
        case selfAndInside
        /// Only the item itself (it is never removed as a whole); its contents follow other rules.
        case selfOnly
        /// The item itself always; things inside only when hand-picked.
        case personalFolder
    }

    public let patterns: [String]
    public let scope: Scope
    public let reason: String

    /// `path` is an absolute path; its components may contain `*`, `?` or `[...]` globs.
    public init(path: String, scope: Scope = .selfAndInside, reason: String) {
        self.patterns = PathNormalizer.components(PathNormalizer.normalize(path) ?? path).map(PathNormalizer.fold)
        self.scope = scope
        self.reason = reason
    }

    /// Does the (folded) component list match this entry's first `count` patterns?
    func matches(_ folded: [String], count: Int) -> Bool {
        for i in 0..<count where !Glob.match(patterns[i], folded[i]) { return false }
        return true
    }
}

/// The protected floor (spec 006 §5): no rule, setting or hand pick can remove anything on it.
/// `protected.json` can add entries but never remove any.
public struct ProtectedFloor: Sendable {
    public let home: Home
    public let entries: [FloorEntry]

    public init(home: Home, additions: [FloorEntry] = []) {
        self.home = home
        self.entries = Self.builtIn(home: home) + additions
    }

    /// Bundle and package extensions: nothing inside one is ever removed on its own.
    public static let packageExtensions: Set<String> = [
        "app", "appex", "bundle", "framework", "plugin", "kext", "xpc", "qlgenerator", "mdimporter",
        "prefpane", "saver", "component", "photoslibrary", "photolibrary", "migratedphotolibrary",
        "aplibrary", "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle", "logicx", "band",
        "xcarchive", "xcodeproj", "xcworkspace", "playground", "rtfd", "pages", "numbers", "key",
        "sparsebundle", "pkg", "mpkg", "theater", "photoslibrary", "lrlibrary", "lrcat-data",
    ]

    /// Media libraries that are never removed, even as a whole.
    public static let libraryExtensions: Set<String> = [
        "photoslibrary", "photolibrary", "migratedphotolibrary", "aplibrary", "musiclibrary",
        "tvlibrary", "imovielibrary", "fcpbundle", "lrlibrary",
    ]

    static func builtIn(home: Home) -> [FloorEntry] {
        let h = home.root.path
        var e: [FloorEntry] = []
        // System folders.
        for p in ["/System", "/bin", "/sbin", "/private/var/db", "/Library/Apple", "/Library/Extensions",
                  "/.DocumentRevisions-V100", "/.Spotlight-V100", "/.fseventsd", "/.vol", "/dev", "/cores"] {
            e.append(FloorEntry(path: p, reason: "\(p) is a system folder"))
        }
        // Folders never removed as a whole.
        for p in ["/Applications", "/Library", "/Users", "/Volumes", "/private", "/usr/local", "/opt", h] {
            e.append(FloorEntry(path: p, scope: .selfOnly, reason: "\(p) is never removed as a whole"))
        }
        // Standard folders are emptied item by item, never removed themselves (zone roots,
        // ~/Library/Caches and friends).
        for p in ["/Library/*", "/private/*", "/private/var/*", h + "/Library/*", h + "/*"] {
            e.append(FloorEntry(path: p, scope: .selfOnly, reason: "standard folders are never removed as a whole"))
        }
        e.append(FloorEntry(path: "/Volumes/*", scope: .selfOnly, reason: "a volume is never removed as a whole"))
        e.append(FloorEntry(path: "/Users/*", scope: .selfOnly, reason: "a home folder is never removed as a whole"))
        // Personal folders.
        for name in ["Documents", "Desktop", "Pictures", "Movies", "Music"] {
            e.append(FloorEntry(path: h + "/" + name, scope: .personalFolder, reason: "~/\(name) holds your own files"))
        }
        // iCloud, cloud sync, keychains, mail, our own files.
        for (rel, why) in [
            ("Library/Mobile Documents", "iCloud Drive"),
            ("Library/CloudStorage", "cloud storage sync folders"),
            ("Library/Keychains", "your keychains"),
            ("Library/Mail", "Mail's data"),
            ("Library/Application Support/TidyMyMac", "TidyMyMac's own files"),
            ("Library/Logs/TidyMyMac", "TidyMyMac's own logs"),
        ] {
            e.append(FloorEntry(path: h + "/" + rel, reason: "~/\(rel) holds \(why)"))
        }
        e.append(FloorEntry(path: "/Library/Application Support/TidyMyMac", reason: "TidyMyMac's own files"))
        e.append(FloorEntry(path: "/Library/Logs/TidyMyMac", reason: "TidyMyMac's own logs"))
        return e
    }

    /// Is `path` allowed to be removed in this context?
    public func verdict(for path: String, context: RemovalContext = .rule) -> FloorVerdict {
        guard let normalized = PathNormalizer.normalize(path) else {
            return .protected("not a plain absolute path")
        }
        let comps = PathNormalizer.components(normalized)
        let folded = comps.map(PathNormalizer.fold)
        if comps.isEmpty { return .protected("/ is never removed") }

        // /usr except /usr/local.
        if folded[0] == "usr" && !(folded.count >= 3 && folded[1] == "local") {
            return .protected("/usr is a system folder")
        }
        if folded.count == 1, folded[0] == "usr" { return .protected("/usr is a system folder") }

        // Anything inside a bundle or package; media libraries themselves.
        for (i, c) in folded.enumerated() {
            let ext = (c as NSString).pathExtension
            if i < folded.count - 1, Self.packageExtensions.contains(ext) {
                return .protected("it is inside the package \(comps[i])")
            }
            if i == folded.count - 1, Self.libraryExtensions.contains(ext) {
                return .protected("\(comps[i]) is a media library")
            }
        }

        for entry in entries {
            let n = entry.patterns.count
            if folded.count >= n, entry.matches(folded, count: n) {
                let isSelf = folded.count == n
                switch entry.scope {
                case .selfAndInside: return .protected(entry.reason)
                case .selfOnly: if isSelf { return .protected(entry.reason) }
                case .personalFolder:
                    if isSelf || context == .rule { return .protected(entry.reason) }
                }
            } else if folded.count < n, ancestorMatches(folded, entry) {
                // Removing an ancestor would remove the protected thing too.
                return .protected("it contains something protected (\(entry.reason))")
            }
        }
        return .allowed
    }

    private func ancestorMatches(_ folded: [String], _ entry: FloorEntry) -> Bool {
        for i in 0..<folded.count where !Glob.match(entry.patterns[i], folded[i]) { return false }
        return true
    }
}

/// fnmatch-style matching of one path component; `*` never crosses a `/`.
public enum Glob {
    public static func match(_ pattern: String, _ name: String) -> Bool {
        if !pattern.contains(where: { "*?[".contains($0) }) { return pattern == name }
        return fnmatch(pattern, name, FNM_PERIOD) == 0
    }

    public static func matchCaseInsensitive(_ pattern: String, _ name: String) -> Bool {
        match(PathNormalizer.fold(pattern), PathNormalizer.fold(name))
    }
}
