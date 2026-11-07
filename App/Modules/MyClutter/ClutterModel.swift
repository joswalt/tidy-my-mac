import DiskAnalysis
import Foundation
import Observation
import RuleEngine
import RunLog
import SafetyFloor

/// State for My Clutter (spec 007 §2): Large & Old · Duplicates · Downloads. Finding and measuring
/// happen in `DiskAnalysis`, removal in `ManualRemover`; this only orchestrates. Nothing is ever
/// ticked except duplicate copies chosen by the keep rule, and everything goes to the Trash.
@MainActor @Observable
final class ClutterModel {
    enum Tab: String, CaseIterable, Identifiable {
        case largeOld, duplicates, downloads
        var id: String { rawValue }
        var title: String {
            switch self {
            case .largeOld: "Large & Old"
            case .duplicates: "Duplicates"
            case .downloads: "Downloads"
            }
        }
    }

    enum Phase: Equatable {
        case browsing, running
        case done(dryRun: Bool)
    }

    static let extraFoldersKey = "clutterExtraFolders"
    static let minimumMBKey = "duplicateMinimumMB"

    weak var app: AppModel?
    var tab: Tab = .largeOld
    var phase: Phase = .browsing
    var lastRun: CleanupEngine.Run?
    var error: String?

    /// Folders added with Add Folder… (spec 014 §3), kept between launches.
    var extraFolders: [String] = UserDefaults.standard.stringArray(forKey: ClutterModel.extraFoldersKey) ?? [] {
        didSet { UserDefaults.standard.set(extraFolders, forKey: Self.extraFoldersKey) }
    }

    // Large & Old
    var largeFiles: [FileEntry]?
    var scanningLarge = false
    var largeFilter = LargeOldFilter.default
    var largeSelection: Set<String> = []

    // Duplicates
    var groups: [DuplicateGroup]?
    var scanningDuplicates = false
    var hashProgress: DuplicateFinder.Progress?
    var keepRule: KeepRule = .oldest
    var duplicateSelection = DuplicateSelection()
    /// Shown briefly when a tick is refused.
    var refusedTick: String?

    // Downloads
    var downloads: [DownloadItem]?
    var scanningDownloads = false
    var downloadsOlderThan: Int? = DownloadsReview.defaultOlderThanDays
    var downloadsSelection: Set<String> = []

    private var cancel = CancelFlag()
    private var hashCache: HashCache?

    var context: CleanupContext? { app?.context }

    var minimumSize: Int64 {
        let mb = UserDefaults.standard.integer(forKey: Self.minimumMBKey)
        return Int64(mb > 0 ? mb : 1) * 1_048_576
    }

    func scope(_ home: Home) -> ClutterScope {
        ClutterScope(folders: ClutterScope.defaultFolders(home) + extraFolders, minimumSize: minimumSize)
    }

    var isScanning: Bool { scanningLarge || scanningDuplicates || scanningDownloads }

    private func cache(_ home: Home) -> HashCache? {
        if hashCache == nil { hashCache = try? HashCache(url: HashCache.defaultURL(home: home)) }
        return hashCache
    }

    private func notIgnored(_ path: String) -> Bool {
        !(app?.ignoreList.ignores(ruleID: ManualRemover.ruleID, path: path) ?? false)
    }

    // MARK: Scans (read-only)

    func onTab() {
        switch tab {
        case .largeOld: if largeFiles == nil { scanLarge() }
        case .duplicates: if groups == nil { scanDuplicates() }
        case .downloads: if downloads == nil { scanDownloads() }
        }
    }

    func rescan() {
        switch tab {
        case .largeOld: scanLarge()
        case .duplicates: scanDuplicates()
        case .downloads: scanDownloads()
        }
    }

    func stop() {
        cancel.set()
        cancel = CancelFlag()
    }

    func scanLarge() {
        guard let ctx = context, !scanningLarge else { return }
        scanningLarge = true
        let scope = scope(ctx.home), flag = cancel
        Task {
            let files = await Task.detached {
                ClutterWalker(home: ctx.home, floor: ctx.floor)
                    .files(scope, includePackages: true, minimumSize: LargeOldFilter.listMinimum) { flag.isSet }
            }.value
            scanningLarge = false
            guard !flag.isSet else { return }
            largeFiles = files.filter { notIgnored($0.path) }
            largeSelection.formIntersection(largeFiles?.map(\.path) ?? [])
        }
    }

    func scanDuplicates() {
        guard let ctx = context, !scanningDuplicates else { return }
        scanningDuplicates = true
        hashProgress = nil
        let scope = scope(ctx.home), flag = cancel, cache = cache(ctx.home)
        Task {
            let found = await Task.detached {
                let files = ClutterWalker(home: ctx.home, floor: ctx.floor).files(scope, includePackages: false) { flag.isSet }
                return DuplicateFinder(cache: cache).groups(files, progress: { p in
                    Task { @MainActor in self.hashProgress = p }
                }, isCancelled: { flag.isSet })
            }.value
            scanningDuplicates = false
            guard !flag.isSet else { return }
            setGroups(found)
        }
    }

    private func setGroups(_ found: [DuplicateGroup]) {
        guard let home = context?.home else { return }
        // Ignored copies leave the set; a set needs two copies left.
        groups = found.compactMap { g in
            let files = g.files.filter { notIgnored($0.path) }
            return files.count > 1 ? DuplicateGroup(id: g.id, size: g.size, files: files) : nil
        }
        duplicateSelection = DuplicateSelection.automatic(groups ?? [], rule: keepRule, home: home)
    }

    func applyKeepRule() {
        guard let home = context?.home, let groups else { return }
        duplicateSelection = DuplicateSelection.automatic(groups, rule: keepRule, home: home)
    }

    func tick(_ file: DuplicateFile, in group: DuplicateGroup, _ on: Bool) {
        if !duplicateSelection.set(file, in: group, on) {
            refusedTick = group.id
            app?.show("One copy always stays. Untick another copy first.")
        }
    }

    func scanDownloads() {
        guard let ctx = context, !scanningDownloads else { return }
        scanningDownloads = true
        let scope = scope(ctx.home), flag = cancel, cache = cache(ctx.home), known = groups
        Task {
            let items = await Task.detached { () -> [DownloadItem] in
                let items = DownloadsReview.items(home: ctx.home, floor: ctx.floor)
                guard let downloads = PathNormalizer.realPath(ctx.home.downloads.path) else { return items }
                // Duplicate downloads (spec 014 §8): the same engine, sets with a copy in Downloads only.
                let groups = known ?? {
                    let files = ClutterWalker(home: ctx.home, floor: ctx.floor).files(scope, includePackages: false) { flag.isSet }
                    return DuplicateFinder(cache: cache).groups(files, requireUnder: downloads, isCancelled: { flag.isSet })
                }()
                return DownloadsReview.markDuplicates(items, groups: groups, downloads: downloads)
            }.value
            scanningDownloads = false
            guard !flag.isSet else { return }
            downloads = items.filter { notIgnored($0.path) }
            downloadsSelection.formIntersection(downloads?.map(\.path) ?? [])
        }
    }

    // MARK: Views of the results

    var visibleLarge: [FileEntry] { largeFilter.apply(largeFiles ?? []) }

    var visibleDownloads: [DownloadItem] {
        let all = (downloads ?? []).sorted { $0.dateAdded < $1.dateAdded }
        guard let days = downloadsOlderThan else { return all }
        return all.filter { DownloadsReview.isOld($0, days: days) }
    }

    var duplicateFreed: Int64 { duplicateSelection.freedBytes(groups ?? []) }

    /// What the footer and confirm show for the current tab.
    var picks: [ManualPick] {
        switch tab {
        case .largeOld:
            return visibleLarge.filter { largeSelection.contains($0.path) }.map {
                ManualPick(path: $0.path, root: $0.root, identity: $0.identity, allocatedBytes: $0.allocatedBytes)
            }
        case .duplicates:
            return (groups ?? []).flatMap { g in
                duplicateSelection.ticked(in: g).map { f in
                    // A clone of a kept copy frees nothing; say so in the summary.
                    let keptClone = g.sharesSpace(f) && g.files.contains { o in !duplicateSelection.contains(o) && o.cloneID == f.cloneID }
                    return ManualPick(path: f.path, root: f.entry.root, identity: f.entry.identity,
                                      allocatedBytes: keptClone ? 0 : f.entry.allocatedBytes, duplicateSet: g.files.map(\.path))
                }
            }
        case .downloads:
            return visibleDownloads.filter { downloadsSelection.contains($0.path) }.map {
                ManualPick(path: $0.path, root: $0.root, identity: $0.identity, allocatedBytes: $0.allocatedBytes)
            }
        }
    }

    var pickedBytes: Int64 {
        tab == .duplicates ? duplicateFreed : picks.reduce(0) { $0 + $1.allocatedBytes }
    }

    var footerLine: String {
        let p = picks
        guard !p.isEmpty else { return "Nothing selected" }
        return "\(p.count.formatted()) \(p.count == 1 ? "item" : "items") · \(sizeString(pickedBytes)) to Trash"
    }

    // MARK: Removal

    func remove(dryRun: Bool) {
        guard let ctx = context else { return }
        let picks = self.picks
        guard !picks.isEmpty else { return }
        phase = .running
        Task {
            do {
                let run = try await Task.detached { try ManualRemover(context: ctx).run(picks, module: "myClutter", dryRun: dryRun) }.value
                lastRun = run
                if !dryRun { forget(Set(run.outcome.done.map(\.path))) }
                phase = .done(dryRun: dryRun)
            } catch {
                self.error = "\(error)"
                phase = .browsing
            }
            app?.reloadRuns()
        }
    }

    /// Drops removed items from every tab's results.
    private func forget(_ removed: Set<String>) {
        largeFiles?.removeAll { removed.contains($0.path) }
        largeSelection.subtract(removed)
        downloads?.removeAll { removed.contains($0.path) }
        downloadsSelection.subtract(removed)
        if let groups {
            self.groups = groups.compactMap { g in
                let files = g.files.filter { !removed.contains($0.path) }
                return files.count > 1 ? DuplicateGroup(id: g.id, size: g.size, files: files) : nil
            }
            duplicateSelection.keepOnly(self.groups ?? [])
        }
    }

    func finish() { phase = .browsing }

    // MARK: Ignore list and settings

    func ignore(_ path: String) {
        app?.ignore(.init(kind: .path, value: path))
        forget([path])
        largeFiles?.removeAll { PathNormalizer.isInside($0.path, path) }
        downloads?.removeAll { PathNormalizer.isInside($0.path, path) }
    }

    func addFolder(_ path: String) {
        guard !extraFolders.contains(path) else { return }
        extraFolders.append(path)
        largeFiles = nil
        groups = nil
        downloads = nil
        onTab()
    }

    func removeFolder(_ path: String) {
        extraFolders.removeAll { $0 == path }
        largeFiles = nil
        groups = nil
        downloads = nil
        onTab()
    }

    /// Settings › Cleanup › Clear Hash Cache (spec 014 §7).
    func clearHashCache() {
        guard let home = context?.home, let cache = cache(home) else { return }
        do {
            try cache.clear()
            app?.show("Hash cache cleared")
        } catch {
            app?.show("\(error)")
        }
    }
}
