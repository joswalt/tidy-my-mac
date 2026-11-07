import Foundation

/// Turns paths into one canonical spelling so the floor can't be dodged by case, Unicode form,
/// `.`/`..`, doubled slashes or the `/System/Volumes/Data` firmlink (spec 006 §5.3, spec 017 §4.2).
public enum PathNormalizer {
    /// Canonical absolute path, or nil if the path is relative or contains `..`.
    /// Keeps the original case (case folding is only for comparisons, see `fold`).
    public static func normalize(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        var parts: [String] = []
        for raw in path.split(separator: "/", omittingEmptySubsequences: true) {
            let part = String(raw)
            if part == "." { continue }
            if part == ".." { return nil }
            parts.append(part.precomposedStringWithCanonicalMapping)
        }
        // The data volume's firmlinked view: /System/Volumes/Data/Users/x is /Users/x.
        if parts.count > 3, parts[0] == "System", parts[1] == "Volumes", parts[2] == "Data" {
            parts.removeFirst(3)
        }
        // /var, /tmp and /etc are symlinks into /private.
        if let first = parts.first, ["var", "tmp", "etc"].contains(first) {
            parts.insert("private", at: 0)
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Path components of a normalized path ("/" has none).
    public static func components(_ normalized: String) -> [String] {
        normalized.split(separator: "/").map(String.init)
    }

    /// Comparison form: NFC and lowercased, because APFS is case-insensitive by default.
    public static func fold(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// True when `path` equals `ancestor` or lies inside it (both normalized), ignoring case.
    public static func isInside(_ path: String, _ ancestor: String) -> Bool {
        let p = components(fold(path)), a = components(fold(ancestor))
        return p.count >= a.count && Array(p.prefix(a.count)) == a
    }

    /// The real path of an existing item with symlinks resolved, normalized; nil if it doesn't exist.
    public static func realPath(_ path: String) -> String? {
        guard let resolved = Darwin.realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return normalize(String(cString: resolved))
    }
}
