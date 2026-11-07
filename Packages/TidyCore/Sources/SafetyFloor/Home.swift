import Foundation

/// The user's folders, passed in everywhere instead of asking the system (spec 017 §2).
/// Only the app's composition root builds the real one; tests build one with `TestHome`.
public struct Home: Sendable, Hashable {
    /// The home folder itself.
    public let root: URL
    /// What `$TMPDIR` expands to in rule roots.
    public let temporaryDirectory: URL
    /// What `$DARWIN_USER_CACHE_DIR` expands to in rule roots.
    public let userCacheDirectory: URL
    /// The user's uid, used for `owner: currentUser` conditions and per-user Trash folders.
    public let userID: UInt32

    public init(root: URL, temporaryDirectory: URL, userCacheDirectory: URL, userID: UInt32) {
        // Not `standardizedFileURL`: it drops the /private prefix of /var paths.
        func canonical(_ u: URL) -> URL { URL(fileURLWithPath: PathNormalizer.normalize(u.path) ?? u.path, isDirectory: true) }
        self.root = canonical(root)
        self.temporaryDirectory = canonical(temporaryDirectory)
        self.userCacheDirectory = canonical(userCacheDirectory)
        self.userID = userID
    }

    public var path: String { root.path }

    public func folder(_ components: String...) -> URL {
        components.reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }
    }

    public var library: URL { folder("Library") }
    public var caches: URL { folder("Library", "Caches") }
    public var logs: URL { folder("Library", "Logs") }
    public var applicationSupport: URL { folder("Library", "Application Support") }
    public var preferences: URL { folder("Library", "Preferences") }
    public var launchAgents: URL { folder("Library", "LaunchAgents") }
    public var trash: URL { folder(".Trash") }
    public var documents: URL { folder("Documents") }
    public var desktop: URL { folder("Desktop") }
    public var downloads: URL { folder("Downloads") }
    public var pictures: URL { folder("Pictures") }
    public var movies: URL { folder("Movies") }
    public var music: URL { folder("Music") }
    public var applications: URL { folder("Applications") }

    /// TidyMyMac's own support folder (on the protected floor).
    public var tidySupport: URL { folder("Library", "Application Support", "TidyMyMac") }
    /// Where run logs go (build spec §6.1).
    public var tidyRunLogs: URL { tidySupport.appendingPathComponent("RunLog", isDirectory: true) }
    /// TidyMyMac's own log folder (on the protected floor).
    public var tidyLogs: URL { folder("Library", "Logs", "TidyMyMac") }

    /// Expands a rule root: an absolute path, or one starting with `~`, `$TMPDIR` or
    /// `$DARWIN_USER_CACHE_DIR` (spec 006 §3.2). Returns nil for anything else.
    public func expand(_ rulePath: String) -> String? {
        func join(_ base: URL, _ rest: Substring) -> String {
            let trimmed = rest.drop(while: { $0 == "/" })
            return trimmed.isEmpty ? base.path : base.path + "/" + trimmed
        }
        if rulePath == "~" { return root.path }
        if rulePath.hasPrefix("~/") { return join(root, rulePath.dropFirst(2)) }
        for (token, base) in [("$TMPDIR", temporaryDirectory), ("$DARWIN_USER_CACHE_DIR", userCacheDirectory)] {
            if rulePath == token { return base.path }
            if rulePath.hasPrefix(token + "/") { return join(base, rulePath.dropFirst(token.count + 1)) }
        }
        if rulePath.hasPrefix("/") { return rulePath }
        return nil
    }
}
