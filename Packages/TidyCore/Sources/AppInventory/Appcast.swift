import Foundation

/// One `<item>` of a Sparkle appcast, with the fields spec 013 §3 reads.
public struct AppcastItem: Sendable, Equatable {
    public var title: String?
    public var pubDate: String?
    public var link: String?
    public var releaseNotesLink: String?
    /// `sparkle:version` (compared with `CFBundleVersion`).
    public var version: String?
    /// `sparkle:shortVersionString` (shown).
    public var shortVersion: String?
    public var os: String?
    public var channel: String?
    public var minimumSystemVersion: String?
    public var maximumSystemVersion: String?
    public var minimumUpdateVersion: String?
    public var hardwareRequirements: [String] = []
    /// The item's own enclosure is a delta (`sparkle:deltaFrom`).
    public var isDelta = false
    public var hasEnclosure = false

    public init() {}
}

/// A namespace-aware appcast reader (spec 013 §3). It matches Sparkle's namespace URI, not the
/// `sparkle:` prefix, and tolerates a trailing `<!-- sparkle-signatures: … -->` block.
/// Filtering logic mirrors Sparkle's SUAppcastDriver and Homebrew's livecheck Sparkle strategy
/// (BSD-2-Clause); see CREDITS.md.
public enum Appcast {
    public static let sparkleNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"

    public struct ParseError: Error, CustomStringConvertible {
        public let description: String
    }

    public static func parse(_ data: Data) throws -> [AppcastItem] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            throw ParseError(description: "not a readable appcast (\(parser.parserError?.localizedDescription ?? "unknown error"))")
        }
        guard delegate.sawRSS else { throw ParseError(description: "not an RSS appcast") }
        return delegate.items
    }

    /// Sparkle's filters, then the highest `sparkle:version` (ties keep the first in the feed).
    /// `installedBuild` is `CFBundleVersion`; `osVersion` like "26.7.1".
    public static func bestItem(_ items: [AppcastItem], installedBuild: String, osVersion: String) -> AppcastItem? {
        var best: AppcastItem?
        for item in items where isEligible(item, installedBuild: installedBuild, osVersion: osVersion) {
            guard let v = item.version else { continue }
            if let b = best?.version, VersionComparator.compare(v, b) != .orderedDescending { continue }
            best = item
        }
        return best
    }

    static func isEligible(_ item: AppcastItem, installedBuild: String, osVersion: String) -> Bool {
        guard item.version != nil, !item.isDelta else { return false }
        if let os = item.os, !["macos", "osx"].contains(os.lowercased()) { return false }
        if item.channel != nil { return false }  // default channel only
        if let min = item.minimumUpdateVersion, VersionComparator.compare(installedBuild, min) == .orderedAscending { return false }
        if let min = item.minimumSystemVersion, VersionComparator.compare(osVersion, min) == .orderedAscending { return false }
        if let max = item.maximumSystemVersion, VersionComparator.compare(osVersion, max) == .orderedDescending { return false }
        // Apple Silicon only: an arm64 requirement always passes; nothing else is defined.
        return true
    }

    final class Delegate: NSObject, XMLParserDelegate {
        var items: [AppcastItem] = []
        var sawRSS = false
        private var current: AppcastItem?
        private var text = ""
        private var deltasDepth = 0
        private var prefixes: [String: [String]] = [:]

        func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
            prefixes[prefix, default: []].append(namespaceURI)
        }

        func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) {
            _ = prefixes[prefix]?.popLast()
        }

        private func isSparkle(_ uri: String?) -> Bool { uri == Appcast.sparkleNamespace }

        /// Attribute value for a Sparkle-namespaced attribute, whatever prefix the feed used.
        private func sparkleAttribute(_ local: String, _ attrs: [String: String]) -> String? {
            for (key, value) in attrs {
                let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2, parts[1] == local, prefixes[parts[0]]?.last == Appcast.sparkleNamespace else { continue }
                return value
            }
            return nil
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                    attributes attrs: [String: String] = [:]) {
            text = ""
            if elementName == "rss" { sawRSS = true }
            if elementName == "item", namespaceURI?.isEmpty != false { current = AppcastItem(); return }
            guard current != nil else { return }
            if isSparkle(namespaceURI), elementName == "deltas" { deltasDepth += 1; return }
            if elementName == "enclosure", namespaceURI?.isEmpty != false, deltasDepth == 0 {
                current!.hasEnclosure = true
                if let v = sparkleAttribute("version", attrs) { current!.version = v }
                if let v = sparkleAttribute("shortVersionString", attrs) { current!.shortVersion = v }
                if let v = sparkleAttribute("os", attrs) { current!.os = v }
                if sparkleAttribute("deltaFrom", attrs) != nil { current!.isDelta = true }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(data: CDATABlock, encoding: .utf8) ?? "" }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = ""
            if elementName == "item", namespaceURI?.isEmpty != false, let item = current { items.append(item); current = nil; return }
            guard current != nil else { return }
            if isSparkle(namespaceURI) {
                switch elementName {
                case "deltas": deltasDepth = max(0, deltasDepth - 1)
                // Enclosure attributes win; the element is the fallback (spec 013 §3).
                case "version": if current!.version == nil, !value.isEmpty { current!.version = value }
                case "shortVersionString": if current!.shortVersion == nil, !value.isEmpty { current!.shortVersion = value }
                case "releaseNotesLink": current!.releaseNotesLink = value
                case "channel": current!.channel = value
                case "minimumSystemVersion": current!.minimumSystemVersion = value
                case "maximumSystemVersion": current!.maximumSystemVersion = value
                case "minimumUpdateVersion": current!.minimumUpdateVersion = value
                case "hardwareRequirements":
                    current!.hardwareRequirements = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                default: break
                }
                return
            }
            guard namespaceURI?.isEmpty != false, deltasDepth == 0 else { return }
            switch elementName {
            case "title": current!.title = value
            case "pubDate": current!.pubDate = value
            case "link": current!.link = value
            default: break
            }
        }
    }
}

/// electron-builder feeds (spec 013 §2–3): `app-update.yml` names the feed, `latest-mac.yml`
/// has the version. Both are tiny YAML files; only top-level `key: value` lines are read.
/// Logic follows Homebrew's livecheck ElectronBuilder strategy (BSD-2-Clause).
public enum ElectronFeed {
    static func topLevel(_ yaml: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in yaml.split(whereSeparator: \.isNewline) {
            guard let first = line.first, !first.isWhitespace, first != "#", first != "-",
                  let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let q = value.first, q == "\"" || q == "'", value.last == q { value = String(value.dropFirst().dropLast()) }
            if out[key] == nil { out[key] = value }
        }
        return out
    }

    /// The `latest-mac.yml` URL for a generic or S3 provider; nil for GitHub and others (they fall
    /// back to Homebrew).
    public static func latestMacURL(appUpdateYAML: String) -> String? {
        let y = topLevel(appUpdateYAML)
        var base: String
        switch y["provider"]?.lowercased() {
        case "generic":
            guard let url = y["url"], !url.isEmpty else { return nil }
            base = url
        case "s3":
            guard let bucket = y["bucket"], !bucket.isEmpty else { return nil }
            let host = y["region"].map { "\(bucket).s3.\($0).amazonaws.com" } ?? "\(bucket).s3.amazonaws.com"
            base = "https://\(host)" + (y["path"].map { "/" + $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) } ?? "")
        default:
            return nil
        }
        while base.hasSuffix("/") { base.removeLast() }
        return base + "/latest-mac.yml"
    }

    /// The top-level `version` of a `latest-mac.yml`.
    public static func version(latestMacYAML: String) -> String? {
        topLevel(latestMacYAML)["version"].flatMap { $0.isEmpty ? nil : $0 }
    }
}
