import Foundation
import RuleEngine
import SafetyFloor

/// Everything the Uninstaller would remove for one app (spec 007 §4: the `.app` itself is always
/// included; every related file is listed and can be unticked).
public struct UninstallPlan: Sendable {
    public let app: InstalledApp
    /// The bundle itself. Root-owned apps get a helper handle from a `rootApps` scan.
    public var appItem: Candidate
    /// Related files: user-level ones found here, root-level ones (with helper handles) added by
    /// `RelatedFileFinder.rootRelated`.
    public var related: [Candidate]
    /// Matches that are kept, and why (shared with a suite app, belongs to another app, …).
    public var kept: [SkippedItem]
    /// Leftover locations not searched because they need Full Disk Access.
    public var needsFullDiskAccess: [String]
    /// Installer package receipts for this app (forgotten through the helper).
    public var receipts: [String]
    /// Files those receipts installed (absolute), used to find root-level items with odd names.
    public var receiptFiles: [String]

    public var allItems: [Candidate] { [appItem] + related }
    public var totalBytes: Int64 { allItems.reduce(0) { $0 + $1.allocatedBytes } }
}

/// Finds an app's related files from the `leftover-location` rules, its `app-override` and its
/// package receipts (build spec §6.5, spec 006 §3.3). Read-only.
public struct RelatedFileFinder: Sendable {
    public static let appRuleID = "app.bundle"
    public static let systemLeftoverRulePrefix = "leftover.system."
    /// Terms shorter than this never match: "Go" would match half the Library.
    public static let minimumTermLength = 4

    public let context: CleanupContext
    /// Bundle IDs of every installed app, Apple's included.
    public let installedBundleIDs: Set<String>
    public let receipts: PackageReceipts?

    public init(context: CleanupContext, installedBundleIDs: Set<String>, receipts: PackageReceipts?) {
        self.context = context
        self.installedBundleIDs = installedBundleIDs
        self.receipts = receipts
    }

    // MARK: Terms

    /// What one app's files are named after.
    public struct Terms: Sendable {
        public let bundleID: String
        public let name: String
        public let teamID: String?
        public let extra: [String]
        public let exclude: [String]
        public let extraPaths: [String]
        public let excludePaths: [String]
        /// Installed apps that share files with this one, with their own terms.
        public let sharedWith: [(id: String, terms: [String])]

        func terms(for match: LeftoverMatch) -> [String] {
            let base: [String] = switch match {
            case .bundleId: [bundleID]
            case .appName: [name]
            case .teamId: teamID.map { [$0] } ?? []
            }
            return (base + extra).filter { $0.count >= RelatedFileFinder.minimumTermLength }
        }
    }

    public func terms(for app: InstalledApp) -> Terms {
        let overrides = context.rules.appOverrides
        let own = overrides.first { $0.bundleId == app.bundleID }
        // Suite partners: listed in our override, or listing us in theirs.
        var partners = Set(own?.sharedWith ?? [])
        for o in overrides where o.sharedWith?.contains(app.bundleID) == true { partners.insert(o.bundleId) }
        let installed = Set(installedBundleIDs.map(PathNormalizer.fold))
        let shared = partners.sorted().filter { installed.contains(PathNormalizer.fold($0)) }.map { id in
            (id: id, terms: [id] + (overrides.first { $0.bundleId == id }?.extraTerms ?? []))
        }
        return Terms(bundleID: app.bundleID, name: app.name, teamID: app.teamID, extra: own?.extraTerms ?? [],
                     exclude: own?.excludeTerms ?? [], extraPaths: own?.extraPaths ?? [], excludePaths: own?.excludePaths ?? [],
                     sharedWith: shared)
    }

    /// Why a matching name must be kept, or nil to offer it.
    func keepReason(_ name: String, terms: Terms) -> String? {
        let f = PathNormalizer.fold(name)
        if DenyList.isAppleItem(name) { return "Apple's own item" }
        if terms.exclude.contains(where: { f.contains(PathNormalizer.fold($0)) }) { return "excluded for this app" }
        for partner in terms.sharedWith where partner.terms.contains(where: { $0.count >= Self.minimumTermLength && f.contains(PathNormalizer.fold($0)) }) {
            return "also used by \(partner.id)"
        }
        // A longer bundle ID that extends ours belongs to another installed app (com.foo.App.Pro).
        let ours = PathNormalizer.fold(terms.bundleID)
        for other in installedBundleIDs {
            let o = PathNormalizer.fold(other)
            if o != ours, o.contains(ours), f.contains(o) { return "belongs to \(other)" }
        }
        return nil
    }

    // MARK: Plan

    public func plan(for app: InstalledApp) -> UninstallPlan {
        let terms = terms(for: app)
        let sizer = Sizer()
        let appItem = Candidate(ruleID: Self.appRuleID, path: app.path, root: app.parent, identity: app.identity, isDirectory: true,
                                allocatedBytes: app.allocatedBytes, newestModification: Date(), action: .trash, risk: .safe,
                                status: .verified)
        var related: [Candidate] = []
        var kept: [SkippedItem] = []
        var needsFDA: [String] = []
        var seen: Set<String> = [PathNormalizer.fold(app.path)]

        var matched: [String] = []
        func consider(_ path: String, root: String, ruleID: String) {
            // A matched folder is one item; nothing inside it is offered on its own.
            if matched.contains(where: { PathNormalizer.isInside(path, $0) }) { return }
            guard seen.insert(PathNormalizer.fold(path)).inserted else { return }
            matched.append(path)
            let name = (path as NSString).lastPathComponent
            if let why = keepReason(name, terms: terms) { kept.append(SkippedItem(ruleID: ruleID, path: path, reason: why)); return }
            if terms.excludePaths.compactMap(context.home.expand).contains(where: { PathNormalizer.isInside(path, $0) || path == $0 }) {
                kept.append(SkippedItem(ruleID: ruleID, path: path, reason: "excluded for this app")); return
            }
            switch evaluate(path, root: root, ruleID: ruleID, sizer: sizer, risk: .safe) {
            case .candidate(let c): related.append(c)
            case .skipped(let why): kept.append(SkippedItem(ruleID: ruleID, path: path, reason: why))
            case .ignored: break
            }
        }

        for location in context.rules.leftoverLocations where location.privilege == .user {
            if location.needsFullDiskAccess && !context.hasFullDiskAccess { needsFDA.append(location.id); continue }
            let wanted = terms.terms(for: location.match).map(PathNormalizer.fold)
            guard !wanted.isEmpty else { continue }
            for (path, root) in Self.walk(location, home: context.home) {
                let name = PathNormalizer.fold((path as NSString).lastPathComponent)
                if wanted.contains(where: name.contains) { consider(path, root: root, ruleID: location.id) }
            }
        }
        for extra in terms.extraPaths {
            guard let expanded = context.home.expand(extra), let parent = PathNormalizer.realPath((expanded as NSString).deletingLastPathComponent)
            else { continue }
            let path = parent + "/" + (expanded as NSString).lastPathComponent
            if FileStatus.lstat(path) != nil { consider(path, root: parent, ruleID: "app-override") }
        }

        var receiptIDs: [String] = []
        var receiptFiles: [String] = []
        if let receipts {
            let bundle = PathNormalizer.fold(app.bundleID)
            let ids = Set(receipts.packages(owning: app.path) + receipts.allPackages().filter { PathNormalizer.fold($0).contains(bundle) })
            receiptIDs = ids.filter { !DenyList.isAppleItem($0) }.sorted()
            receiptFiles = receiptIDs.flatMap(receipts.files(of:))
        }
        related.sort { $0.path < $1.path }
        return UninstallPlan(app: app, appItem: appItem, related: related, kept: kept, needsFullDiskAccess: needsFDA,
                             receipts: receiptIDs, receiptFiles: receiptFiles)
    }

    /// Root-level related files from the helper's `libraryLeftovers` and `launchItems` scans: names
    /// that carry the app's terms, or folders its package receipts installed into.
    public func rootRelated(for plan: UninstallPlan, items: [HelperFoundItem]) -> (offered: [Candidate], kept: [SkippedItem]) {
        let terms = terms(for: plan.app)
        let wanted = terms.terms(for: .bundleId).map(PathNormalizer.fold)
        let receiptFiles = plan.receiptFiles.compactMap(PathNormalizer.normalize).map(PathNormalizer.fold)
        var offered: [Candidate] = []
        var kept: [SkippedItem] = []
        for item in items where item.zone == .libraryLeftovers || item.zone == .launchItems {
            let name = (item.path as NSString).lastPathComponent
            let folded = PathNormalizer.fold(PathNormalizer.normalize(item.path) ?? item.path)
            let byName = wanted.contains(where: PathNormalizer.fold(name).contains)
            let byReceipt = receiptFiles.contains { $0 == folded || $0.hasPrefix(folded + "/") }
            guard byName || byReceipt else { continue }
            let ruleID = Self.systemLeftoverRulePrefix + item.zone.rawValue
            if let why = keepReason(name, terms: terms) { kept.append(SkippedItem(ruleID: ruleID, path: item.path, reason: why)); continue }
            offered.append(Self.helperCandidate(item, ruleID: ruleID, risk: .safe))
        }
        return (offered.sorted { $0.path < $1.path }, kept)
    }

    static func helperCandidate(_ item: HelperFoundItem, ruleID: String, risk: RuleRisk) -> Candidate {
        Candidate(ruleID: ruleID, path: item.path, root: (item.path as NSString).deletingLastPathComponent,
                  identity: ItemIdentity(device: 0, inode: 0), isDirectory: item.isDirectory, allocatedBytes: item.allocatedBytes,
                  newestModification: item.modified, action: .trash, risk: risk, status: .verified, helperHandle: item.handle)
    }

    // MARK: Walking and checking

    /// Items of a leftover location: its children, and their children down to `maxDepth` (≤ 3).
    /// Never descends into packages or through symlinks. Returns (item, containment root).
    static func walk(_ location: LeftoverLocation, home: Home) -> [(String, String)] {
        guard let expanded = home.expand(location.root), let root = PathNormalizer.realPath(expanded),
              FileStatus.lstat(root)?.isDirectory == true else { return [] }
        let depth = min(max(location.maxDepth ?? 1, 1), 3)
        var out: [(String, String)] = []
        func visit(_ dir: String, level: Int) {
            for name in AppCatalog.children(dir) {
                let p = dir + "/" + name
                out.append((p, root))
                if level < depth, let st = FileStatus.lstat(p), st.isDirectory, !st.isSymlink,
                   !ProtectedFloor.packageExtensions.contains(PathNormalizer.fold((name as NSString).pathExtension)) {
                    visit(p, level: level + 1)
                }
            }
        }
        visit(root, level: 1)
        return out
    }

    enum Evaluation { case candidate(Candidate), skipped(String), ignored }

    /// The same per-item checks the rule scanner makes (spec 006 §5): not a symlink, inside its
    /// root, not on the floor, not locked, not spanning volumes. Sized by allocated size.
    func evaluate(_ path: String, root: String, ruleID: String, sizer: Sizer, risk: RuleRisk) -> Evaluation {
        guard let st = FileStatus.lstat(path) else { return .ignored }
        if st.isSymlink { return .skipped("it is a symbolic link") }
        do { try Containment.validate(item: path, root: root) } catch { return .skipped(error.description) }
        if case .protected(let why) = context.floor.verdict(for: path, context: .rule) { return .skipped("protected: \(why)") }
        let m = sizer.measure(path)
        if m.crossesVolume { return .skipped("it contains another volume") }
        if m.containsLockedItem { return .skipped("it contains a locked item") }
        return .candidate(Candidate(ruleID: ruleID, path: path, root: root, identity: st.identity, isDirectory: st.isDirectory,
                                    allocatedBytes: m.allocatedBytes, newestModification: m.newestModification, action: .trash,
                                    risk: risk, status: .verified))
    }
}
