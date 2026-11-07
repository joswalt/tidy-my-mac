import AppInventory
import AppKit
import HelperProtocol
import Observation
import RuleEngine
import RunLog
import SafetyFloor

/// State for Applications (spec 007 §2): Uninstaller · Unused · Leftovers · Installers · Updates.
/// Everything that touches the file system happens in `AppInventory`; this only orchestrates.
@MainActor @Observable
final class ApplicationsModel {
    enum Tab: String, CaseIterable, Identifiable {
        case uninstaller, unused, leftovers, installers, updates
        var id: String { rawValue }
        var title: String {
            switch self {
            case .uninstaller: "Uninstaller"
            case .unused: "Unused"
            case .leftovers: "Leftovers"
            case .installers: "Installers"
            case .updates: "Updates"
            }
        }
    }

    enum Phase: Equatable {
        case browsing, running
        case done(dryRun: Bool)
    }

    weak var app: AppModel?
    let services: AppServices?
    var tab: Tab = .uninstaller

    // MARK: Inventory and Uninstaller
    var listing: AppCatalog.Listing?
    var loadingApps = false
    var apps: [InstalledApp] { listing?.apps ?? [] }
    /// Apps ticked for uninstall (by path).
    var ticked: Set<String> = []
    var focused: String?
    var plans: [String: UninstallPlan] = [:]
    var planning: Set<String> = []
    /// Related items the user unticked (candidate ids). The app bundle itself can't be unticked.
    var unticked: Set<String> = []
    var running: Set<String> = []
    var phase: Phase = .browsing
    var lastRun: CleanupEngine.Run?
    var error: String?
    /// One helper scan per session of the zones apps leave things in.
    private var helperItems: [HelperFoundItem]?

    // MARK: Unused
    var unusedDays = UnusedApps.defaultThreshold

    // MARK: Leftovers
    var leftovers: [LeftoverGroup]?
    var leftoverNeedsFDA: [String] = []
    var scanningLeftovers = false
    var leftoverSelection = Selection()

    // MARK: Installers
    let installers = ScanSession(module: "applications")

    // MARK: Updates
    var updates: [UpdateStatus] = []
    var updatesChecked: Date?
    var checkingUpdates = false
    var macOSPassive: MacOSUpdates.Passive = .unknown
    var macOSList: [MacOSUpdates.Update]?
    var macOSError: String?
    var checkingMacOS = false

    init(services: AppServices?) {
        self.services = services
        if let stored = services?.cache.loadUpdates() {
            updates = stored.statuses
            updatesChecked = stored.checked
        }
    }

    var updateCount: Int { updates.filter { $0.state == .updateAvailable }.count }

    var context: CleanupContext? { app?.context }

    // MARK: Loading

    func loadApps(force: Bool = false) {
        guard let services, !loadingApps, force || listing == nil else { return }
        loadingApps = true
        refreshRunning()
        Task {
            let listing = await Task.detached { services.catalog.list() }.value
            self.listing = listing
            loadingApps = false
            plans = [:]
            helperItems = nil
            ticked.formIntersection(listing.apps.map(\.path))
            if focused == nil || !listing.apps.contains(where: { $0.path == focused }) { focused = listing.apps.first?.path }
            if let f = focused { makePlan(f) }
            if tab == .updates { checkUpdatesIfDue() }
        }
    }

    func refreshRunning() {
        running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func isRunning(_ app: InstalledApp) -> Bool { running.contains(app.bundleID) }

    func quit(_ app: InstalledApp) {
        for r in NSWorkspace.shared.runningApplications where r.bundleIdentifier == app.bundleID { r.terminate() }
        Task {
            try? await Task.sleep(for: .seconds(2))
            refreshRunning()
        }
    }

    // MARK: Plans

    func app(_ path: String) -> InstalledApp? { apps.first { $0.path == path } }

    func makePlan(_ path: String) {
        guard let app = app(path), let ctx = context, let services, plans[path] == nil, !planning.contains(path) else { return }
        planning.insert(path)
        let installed = listing?.allBundleIDs ?? []
        let helperReady = self.app?.helper.state.isReady == true
        Task {
            let finder = RelatedFileFinder(context: ctx, installedBundleIDs: installed, receipts: services.receipts)
            var plan = await Task.detached { finder.plan(for: app) }.value
            if helperReady, let items = await zoneItems() {
                let root = finder.rootRelated(for: plan, items: items)
                plan.related += root.offered
                plan.kept += root.kept
                if app.needsHelper(userID: ctx.home.userID),
                   let handle = items.first(where: { $0.zone == .rootApps && $0.path == app.path })?.handle {
                    plan.appItem.helperHandle = handle
                }
            }
            plans[path] = plan
            planning.remove(path)
        }
    }

    /// libraryLeftovers, launchItems and rootApps, scanned once per session (005 §5).
    private func zoneItems() async -> [HelperFoundItem]? {
        if let helperItems { return helperItems }
        guard let helper = app?.helper, helper.state.isReady else { return nil }
        let items = await helper.found(in: [.libraryLeftovers, .launchItems, .rootApps])
        helperItems = items
        return items
    }

    /// Why an app can't be uninstalled right now, or nil.
    func blocker(_ app: InstalledApp) -> String? {
        if isRunning(app) { return "\(app.name) is open. Quit it first." }
        if app.needsHelper(userID: context?.home.userID ?? 0) {
            guard self.app?.helper.state.isReady == true else { return "\(app.name) belongs to the system. Install the admin helper to remove it." }
            if let plan = plans[app.path], plan.appItem.helperHandle == nil { return "The admin helper won't remove \(app.name)." }
        }
        return nil
    }

    func selectedItems(_ plan: UninstallPlan) -> [Candidate] {
        [plan.appItem] + plan.related.filter { !unticked.contains($0.id) }
    }

    /// Ticked apps whose plans are ready and that nothing blocks.
    var readyPlans: [UninstallPlan] {
        ticked.compactMap { plans[$0] }.filter { blocker($0.app) == nil }.sorted { $0.app.name < $1.app.name }
    }

    var uninstallSummary: CleanupSummary { CleanupSummary(readyPlans.flatMap(selectedItems)) }

    var uninstallAdminItems: [Candidate] { readyPlans.flatMap(selectedItems).filter(\.viaHelper) }

    func tick(_ path: String, _ on: Bool) {
        if on { ticked.insert(path); makePlan(path) } else { ticked.remove(path) }
    }

    // MARK: Uninstall

    func uninstall(dryRun: Bool) {
        let plans = readyPlans
        guard !plans.isEmpty else { return }
        let batches = plans.map { (owner: $0.app.bundleID, items: selectedItems($0), receipts: $0.receipts) }
        run(batches, dryRun: dryRun) { [weak self] in
            guard let self else { return }
            for p in plans { ticked.remove(p.app.path) }
            if !dryRun { helperItems = nil; loadApps(force: true) }
        }
    }

    /// Removes leftovers ticked in the Leftovers tab, grouped by their missing owner.
    func removeLeftovers(dryRun: Bool) {
        let groups = (leftovers ?? []).compactMap { g -> (owner: String, items: [Candidate], receipts: [String])? in
            let items = leftoverSelection.selected(from: g.items)
            return items.isEmpty ? nil : (g.ownerBundleID, items, [])
        }
        guard !groups.isEmpty else { return }
        run(groups, dryRun: dryRun) { [weak self] in
            guard let self, !dryRun else { return }
            helperItems = nil
            scanLeftovers()
        }
    }

    /// One run, one log (build spec §6.1): root-owned apps first through the helper, then the
    /// user-level items, then root-level related files for owners whose app is gone, then receipts.
    private func run(_ groups: [(owner: String, items: [Candidate], receipts: [String])], dryRun: Bool,
                     after: @escaping () -> Void) {
        guard let ctx = context, let services, let app else { return }
        phase = .running
        Task {
            // 1. Root-owned app bundles through the helper (rootApps).
            let rootApps = groups.flatMap { g in g.items.filter { $0.ruleID == RelatedFileFinder.appRuleID && $0.viaHelper } }
            var extra: [RunItem] = []
            var blocked: [String: String] = [:]
            if !rootApps.isEmpty {
                let results = await removeThroughHelper(rootApps, dryRun: dryRun)
                extra += results
                for g in groups {
                    guard let appItem = g.items.first(where: { $0.ruleID == RelatedFileFinder.appRuleID && $0.viaHelper }) else { continue }
                    if let r = results.first(where: { $0.path == appItem.path }), r.result != .done {
                        blocked[g.owner] = "the app itself wasn't removed (\(r.reason ?? "the helper refused"))"
                    }
                }
            }
            let batches = groups.map { RemovalBatch(ownerBundleID: $0.owner, items: $0.items, blockedReason: blocked[$0.owner]) }
            let helperRelated = groups.map { g in (g.owner, g.items.filter { $0.viaHelper && $0.ruleID != RelatedFileFinder.appRuleID }, g.receipts) }
            let engine = AppRemovalEngine(context: ctx, signatures: services.signatures)
            do {
                let run = try await engine.run(batches, dryRun: dryRun, extraItems: extra) { owners in
                    await self.rootRelated(helperRelated, removedOwners: owners, dryRun: dryRun)
                }
                lastRun = run
                phase = .done(dryRun: dryRun)
            } catch {
                self.error = "\(error)"
                phase = .browsing
            }
            app.helper.endAuthorization()
            app.reloadRuns()
            after()
        }
    }

    private func rootRelated(_ groups: [(String, [Candidate], [String])], removedOwners: Set<String>, dryRun: Bool) async -> [RunItem] {
        var out: [RunItem] = []
        var go: [Candidate] = []
        var receipts: [String] = []
        for (owner, items, rs) in groups {
            if removedOwners.contains(owner) {
                go += items
                receipts += rs
            } else {
                out += items.map { RunItem(ruleID: $0.ruleID, path: $0.path, allocatedBytes: $0.allocatedBytes, action: .trash,
                                           result: .skipped, reason: "its app wasn't removed") }
            }
        }
        if !go.isEmpty { out += await removeThroughHelper(go, dryRun: dryRun) }
        for id in receipts {
            var result: RunResult = .done
            var why: String?
            do { _ = try await app?.helper.send(.forgetReceipt(packageID: id, dryRun: dryRun)) } catch { result = .failed; why = "\(error)" }
            out.append(RunItem(ruleID: "app.receipt", path: id, allocatedBytes: 0, action: .operation("forgetReceipt"), result: result, reason: why))
        }
        return out
    }

    private func removeThroughHelper(_ items: [Candidate], dryRun: Bool) async -> [RunItem] {
        guard let helper = app?.helper else { return [] }
        let byHandle = Dictionary(uniqueKeysWithValues: items.compactMap { c in c.helperHandle.map { ($0, c) } })
        do {
            let reply = try await helper.send(.remove(handles: items.compactMap { $0.helperHandle.map(HelperHandle.init) }, dryRun: dryRun, jobID: UUID()))
            guard case .results(let rs) = reply else { return [] }
            return rs.map { r in
                let c = r.handle.flatMap { byHandle[$0.raw] }
                return RunItem(ruleID: c?.ruleID ?? "helper", path: c?.path ?? r.path, allocatedBytes: c?.allocatedBytes ?? r.allocatedBytes,
                               action: .trash, result: r.outcome == .done ? .done : (r.outcome == .skipped ? .skipped : .failed),
                               reason: r.reason, trashPath: r.trashPath, helperLedgerID: r.ledgerID?.uuidString)
            }
        } catch {
            return items.map { RunItem(ruleID: $0.ruleID, path: $0.path, allocatedBytes: $0.allocatedBytes, action: .trash,
                                       result: .skipped, reason: "\(error)") }
        }
    }

    func finish() {
        phase = .browsing
        lastRun = nil
    }

    // MARK: Leftovers

    func scanLeftovers() {
        guard let ctx = context, !scanningLeftovers else { return }
        if listing == nil { loadApps() }
        scanningLeftovers = true
        Task {
            while listing == nil && loadingApps { try? await Task.sleep(for: .milliseconds(200)) }
            let installed = listing?.allBundleIDs ?? []
            let scanner = LeftoverScanner(context: ctx, installedBundleIDs: installed)
            let result = await Task.detached { scanner.scan() }.value
            var groups = result.groups
            if let items = await zoneItems() { groups = LeftoverScanner.merge(groups, scanner.rootGroups(items: items)) }
            let ignore = app?.ignoreList ?? IgnoreList()
            groups = groups.compactMap { g in
                var g = g
                g.items = g.items.filter { !ignore.ignores($0) }
                return g.items.isEmpty ? nil : g
            }
            leftovers = groups
            leftoverNeedsFDA = result.needsFullDiskAccess
            leftoverSelection = Selection()  // caution: nothing ticked by default
            scanningLeftovers = false
        }
    }

    var leftoverSummary: CleanupSummary { CleanupSummary(leftoverSelection.selected(from: (leftovers ?? []).flatMap(\.items))) }

    // MARK: Updates (spec 013)

    var checkAutomatically: Bool {
        UserDefaults.standard.object(forKey: "checkAppUpdatesAutomatically") as? Bool ?? true
    }

    /// At most once a day, when the Updates tab or Tidy Up opens (spec 013 §6).
    func checkUpdatesIfDue() {
        macOSPassive = MacOSUpdates.readPlist()
        guard checkAutomatically else { return }
        if let last = updatesChecked, Date().timeIntervalSince(last) < UpdateCache.automaticInterval { return }
        checkUpdates()
    }

    func checkUpdates() {
        guard let services, let ctx = context, !checkingUpdates else { return }
        macOSPassive = MacOSUpdates.readPlist()
        checkingUpdates = true
        let ignored = Set(ctx.rules.updateOverrides.map(\.bundleId))
        Task {
            if listing == nil { loadApps() }
            while listing == nil { try? await Task.sleep(for: .milliseconds(200)) }
            let apps = self.apps
            let casks = await services.cache.casks(fetcher: services.fetcher)
            let installedCasks = await Task.detached { InstalledCasks(caskroom: services.caskroom) }.value
            let checker = UpdateChecker(fetcher: services.fetcher, osVersion: UpdateChecker.currentOSVersion,
                                        ignoredBundleIDs: ignored, installedCasks: installedCasks)
            let statuses = await checker.check(apps, casks: casks)
            updates = statuses
            updatesChecked = Date()
            try? services.cache.save(UpdateCache.Stored(checked: updatesChecked!, statuses: statuses))
            checkingUpdates = false
        }
    }

    func checkAppleUpdates() {
        guard !checkingMacOS else { return }
        checkingMacOS = true
        macOSError = nil
        Task {
            do { macOSList = try await MacOSUpdates.list() } catch { macOSError = "\(error)" }
            macOSPassive = MacOSUpdates.readPlist()
            checkingMacOS = false
        }
    }

    func openSoftwareUpdate() {
        if let url = URL(string: MacOSUpdates.settingsURL) { NSWorkspace.shared.open(url) }
    }

    /// Puts a shown command (the `brew upgrade` hint) on the clipboard. Nothing is run.
    func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    func open(_ status: UpdateStatus) {
        if status.source == .appStore, let url = URL(string: "macappstore://showUpdatesPage") {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: status.appPath), configuration: NSWorkspace.OpenConfiguration())
    }
}
