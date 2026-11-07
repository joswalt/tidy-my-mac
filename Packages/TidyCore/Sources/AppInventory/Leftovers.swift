import Foundation
import RuleEngine
import SafetyFloor

/// Files left behind by apps that are no longer installed, grouped by the missing app
/// (build spec §6.5). Risk `caution`: nothing is ticked by default. Never `com.apple.*`.
public struct LeftoverGroup: Sendable, Identifiable {
    public let ownerBundleID: String
    public var items: [Candidate]
    /// Another app from the same developer (same first two bundle ID parts) is still installed,
    /// so some of these may be shared helpers. Shown with a note.
    public var vendorHasInstalledApp: Bool

    public var id: String { ownerBundleID }
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.allocatedBytes } }
}

public struct LeftoverScanner: Sendable {
    public let context: CleanupContext
    /// Bundle IDs of every installed app, Apple's included.
    public let installedBundleIDs: Set<String>

    public init(context: CleanupContext, installedBundleIDs: Set<String>) {
        self.context = context
        self.installedBundleIDs = installedBundleIDs
    }

    public struct Result: Sendable {
        public var groups: [LeftoverGroup]
        public var skipped: [SkippedItem]
        public var needsFullDiskAccess: [String]
    }

    /// User-level leftovers, from the `leftover-location` rules.
    public func scan() -> Result {
        let finder = RelatedFileFinder(context: context, installedBundleIDs: installedBundleIDs, receipts: nil)
        let running = ((try? context.guards.runningBundleIDs()) ?? []).map(PathNormalizer.fold)
        let sizer = Sizer()
        var byOwner: [String: [Candidate]] = [:]
        var skipped: [SkippedItem] = []
        var needsFDA: [String] = []
        for location in context.rules.leftoverLocations where location.privilege == .user && location.match == .bundleId {
            if location.needsFullDiskAccess && !context.hasFullDiskAccess { needsFDA.append(location.id); continue }
            guard let expanded = context.home.expand(location.root), let root = PathNormalizer.realPath(expanded) else { continue }
            for name in AppCatalog.children(root) {
                guard let owner = Self.ownerBundleID(fromName: name), isMissing(owner, running: Set(running)) else { continue }
                let path = root + "/" + name
                if root == PathNormalizer.realPath(context.home.launchAgents.path), Self.launchProgramExists(path) != false { continue }
                switch finder.evaluate(path, root: root, ruleID: location.id, sizer: sizer, risk: .caution) {
                case .candidate(let c): byOwner[owner, default: []].append(c)
                case .skipped(let why): skipped.append(SkippedItem(ruleID: location.id, path: path, reason: why))
                case .ignored: break
                }
            }
        }
        return Result(groups: groups(byOwner), skipped: skipped, needsFullDiskAccess: needsFDA)
    }

    /// Root-level leftovers from the helper's `libraryLeftovers` and `launchItems` scans.
    public func rootGroups(items: [HelperFoundItem]) -> [LeftoverGroup] {
        let running = Set(((try? context.guards.runningBundleIDs()) ?? []).map(PathNormalizer.fold))
        var byOwner: [String: [Candidate]] = [:]
        for item in items where item.zone == .libraryLeftovers || item.zone == .launchItems {
            let name = (item.path as NSString).lastPathComponent
            guard let owner = Self.ownerBundleID(fromName: name), isMissing(owner, running: running) else { continue }
            if item.zone == .launchItems && item.launchProgramExists != false { continue }
            byOwner[owner, default: []].append(RelatedFileFinder.helperCandidate(
                item, ruleID: RelatedFileFinder.systemLeftoverRulePrefix + item.zone.rawValue, risk: .caution))
        }
        return groups(byOwner)
    }

    /// Merges root groups into user groups by owner.
    public static func merge(_ a: [LeftoverGroup], _ b: [LeftoverGroup]) -> [LeftoverGroup] {
        var map = Dictionary(uniqueKeysWithValues: a.map { ($0.ownerBundleID, $0) })
        for g in b { if map[g.ownerBundleID] != nil { map[g.ownerBundleID]!.items += g.items } else { map[g.ownerBundleID] = g } }
        return sorted(Array(map.values))
    }

    func groups(_ found: [String: [Candidate]]) -> [LeftoverGroup] {
        // An owner that extends another (com.foo.app.agent → com.foo.app) joins that group.
        var byOwner: [String: [Candidate]] = [:]
        for owner in found.keys.sorted(by: { $0.count < $1.count }) {
            let f = PathNormalizer.fold(owner)
            let parent = byOwner.keys.first { f.hasPrefix(PathNormalizer.fold($0) + ".") }
            byOwner[parent ?? owner, default: []] += found[owner]!
        }
        let vendors = Set(installedBundleIDs.map { Self.vendor(PathNormalizer.fold($0)) })
        return Self.sorted(byOwner.map { owner, items in
            LeftoverGroup(ownerBundleID: owner, items: items.sorted { $0.path < $1.path },
                          vendorHasInstalledApp: vendors.contains(Self.vendor(PathNormalizer.fold(owner))))
        })
    }

    static func sorted(_ g: [LeftoverGroup]) -> [LeftoverGroup] {
        g.sorted { ($0.vendorHasInstalledApp ? 1 : 0, -$0.totalBytes, $0.ownerBundleID) < ($1.vendorHasInstalledApp ? 1 : 0, -$1.totalBytes, $1.ownerBundleID) }
    }

    /// No installed or running app owns `owner`: not installed, not related by prefix to an
    /// installed bundle ID (an app's helper or extension), not running, not ours, not Apple's,
    /// and Launch Services doesn't know it either.
    func isMissing(_ owner: String, running: Set<String>) -> Bool {
        let o = PathNormalizer.fold(owner)
        if DenyList.isAppleItem(owner) || o.hasPrefix("io.github.joswalt.tidymymac") { return false }
        if running.contains(where: { $0 == o || $0.hasPrefix(o + ".") || o.hasPrefix($0 + ".") }) { return false }
        for id in installedBundleIDs {
            let i = PathNormalizer.fold(id)
            if i == o || i.hasPrefix(o + ".") || o.hasPrefix(i + ".") { return false }
        }
        guard let installed = try? context.guards.isAppInstalled(bundleID: owner) else { return false }  // can't tell: keep
        return !installed
    }

    static func vendor(_ id: String) -> String { id.split(separator: ".").prefix(2).joined(separator: ".") }

    /// The bundle ID a Library item is named after, or nil if the name doesn't look like one.
    /// Handles `.plist`, `.savedState`, ByHost `<id>.<hardware UUID>.plist`, `group.` and
    /// Team ID prefixes (`ABCDE12345.com.foo.app`).
    public static func ownerBundleID(fromName raw: String) -> String? {
        var name = raw
        for ext in [".plist", ".savedState", ".binarycookies", ".lockfile"] where name.lowercased().hasSuffix(ext.lowercased()) {
            name = String(name.dropLast(ext.count))
        }
        var parts = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if let last = parts.last, parts.count > 3, isHardwareID(last) { parts.removeLast() }
        if parts.first == "group" { parts.removeFirst() }
        if let first = parts.first, first.count == 10, first.allSatisfy({ $0.isUppercase || $0.isNumber }), parts.count > 3 {
            parts.removeFirst()
        }
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }) else {
            return nil
        }
        // The first part is a reverse-DNS top-level domain: letters only.
        guard let tld = parts.first, (2...12).contains(tld.count), tld.allSatisfy(\.isLetter) else { return nil }
        return parts.joined(separator: ".")
    }

    /// ByHost files end in the Mac's hardware UUID (or its last 12 hex digits).
    static func isHardwareID(_ s: String) -> Bool {
        let hex = s.replacingOccurrences(of: "-", with: "")
        return hex.count >= 12 && hex.allSatisfy(\.isHexDigit)
    }

    /// For a launch agent plist: does its program exist? nil when unreadable.
    static func launchProgramExists(_ plist: String) -> Bool? {
        guard let dict = AppBundleReader.plist(plist) else { return nil }
        let program = dict["Program"] as? String ?? (dict["ProgramArguments"] as? [String])?.first
        guard let program, program.hasPrefix("/") else { return nil }
        return FileStatus.lstat(program) != nil
    }
}

/// Unused apps (build spec §6.5): not opened in N days by Spotlight's last-used date. Apps with
/// no date go in their own group. This only lists; removal happens in the Uninstaller.
public enum UnusedApps {
    public static let thresholds = [30, 90, 180, 365]
    public static let defaultThreshold = 90

    public static func split(_ apps: [InstalledApp], days: Int, now: Date = Date()) -> (unused: [InstalledApp], noDate: [InstalledApp]) {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let unused = apps.filter { ($0.lastUsed ?? .distantFuture) < cutoff }.sorted { $0.lastUsed! < $1.lastUsed! }
        let noDate = apps.filter { $0.lastUsed == nil }
        return (unused, noDate)
    }
}
