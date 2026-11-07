import AppInventory
import AppKit
import RuleEngine
import SwiftUI

/// Applications (spec 007 §2): Uninstaller · Unused · Leftovers · Installers · Updates.
struct ApplicationsView: View {
    @Environment(AppModel.self) private var app

    var model: ApplicationsModel { app.applications }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            switch model.phase {
            case .running:
                ProgressView("Moving to the Trash…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done(let dry):
                if let run = model.lastRun { RunResultView(run: run, dryRun: dry) { model.finish() } }
            case .browsing:
                switch model.tab {
                case .uninstaller: UninstallerTab(model: model)
                case .unused: UnusedTab(model: model)
                case .leftovers: LeftoversTab(model: model)
                case .installers: InstallersTab(session: model.installers)
                case .updates: UpdatesTab(model: model)
                }
            }
        }
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Tab", selection: $model.tab) {
                    ForEach(ApplicationsModel.Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(model.phase != .browsing)
            }
            ToolbarItem {
                Button { refresh() } label: { Label("Scan Again", systemImage: "arrow.clockwise") }
                    .help("Look again (⌘R)")
                    .keyboardShortcut("r")
                    .disabled(model.phase != .browsing)
            }
        }
        .onAppear { model.loadApps(); onTab(model.tab) }
        .onChange(of: model.tab) { _, tab in onTab(tab) }
        .alert("Something went wrong", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") {}
        } message: { Text(model.error ?? "") }
    }

    var subtitle: String {
        switch model.tab {
        case .uninstaller, .unused: model.loadingApps ? "Looking for apps…" : "\(model.apps.count) apps"
        case .leftovers: model.leftovers.map { "\($0.count) missing apps left files" } ?? ""
        case .installers: model.installers.report.map { "\(sizeString($0.totalBytes)) found" } ?? ""
        case .updates: model.updateCount == 1 ? "1 update" : "\(model.updateCount) updates"
        }
    }

    func onTab(_ tab: ApplicationsModel.Tab) {
        switch tab {
        case .leftovers: if model.leftovers == nil { model.scanLeftovers() }
        case .installers: if model.installers.phase == .idle { model.installers.scan() }
        case .updates: model.checkUpdatesIfDue()
        case .uninstaller, .unused: break
        }
    }

    func refresh() {
        model.refreshRunning()
        switch model.tab {
        case .uninstaller, .unused: model.loadApps(force: true)
        case .leftovers: model.scanLeftovers()
        case .installers: model.installers.scan()
        case .updates: model.checkUpdates()
        }
    }
}

/// The app's own icon, from Launch Services (no file reads in the UI).
struct AppIcon: View {
    let path: String
    var size: CGFloat = 32
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: size, height: size)
    }
}

// MARK: - Uninstaller

struct UninstallerTab: View {
    @Bindable var model: ApplicationsModel
    @Environment(AppModel.self) private var app
    @State private var search = ""
    @State private var showConfirm = false

    var filtered: [InstalledApp] {
        search.isEmpty ? model.apps : model.apps.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        if model.loadingApps && model.listing == nil {
            ProgressView("Looking for apps…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.apps.isEmpty {
            EmptyStateView(symbol: "square.grid.2x2", message: "No apps you can uninstall were found. Apple's own apps are never listed.")
        } else {
            HSplitView {
                List(selection: $model.focused) {
                    ForEach(filtered) { a in
                        AppRow(model: model, app: a).tag(a.path)
                    }
                }
                .searchable(text: $search, placement: .sidebar, prompt: "Search apps")
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
                .onChange(of: model.focused) { _, path in if let path { model.makePlan(path) } }
                if let path = model.focused, let a = model.app(path) {
                    PlanDetail(model: model, app: a)
                } else {
                    EmptyStateView(symbol: "square.grid.2x2", message: "Pick an app to see what it left on your Mac.")
                }
            }
            FooterBar(summary: footerLine) {
                Button("Dry Run") { model.uninstall(dryRun: true) }
                    .help("List exactly what would be moved, without changing anything")
                    .disabled(model.readyPlans.isEmpty)
                Button(model.readyPlans.count > 1 ? "Uninstall \(model.readyPlans.count) Apps…" : "Uninstall…") { showConfirm = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.readyPlans.isEmpty)
            }
            .uninstallConfirm($showConfirm, model: model)
        }
    }

    var footerLine: String {
        let s = model.uninstallSummary
        guard s.itemCount > 0 else { return model.ticked.isEmpty ? "Tick the apps to uninstall" : "Nothing ready to uninstall" }
        let apps = model.readyPlans.count
        return "\(apps) \(apps == 1 ? "app" : "apps") · \(s.itemCount) items · \(sizeString(s.trashBytes)) to Trash"
    }
}

struct AppRow: View {
    @Bindable var model: ApplicationsModel
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { model.ticked.contains(app.path) }, set: { model.tick(app.path, $0) }))
                .labelsHidden()
                .accessibilityLabel("Uninstall \(app.name)")
            AppIcon(path: app.path, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text(app.versionText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if model.isRunning(app) {
                Text("Open").font(.caption).foregroundStyle(.orange).help("\(app.name) is running")
            }
            if app.needsHelper(userID: model.context?.home.userID ?? 0) {
                AdminBadge()
            }
            Text(sizeString(model.plans[app.path]?.totalBytes ?? app.allocatedBytes)).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

struct PlanDetail: View {
    @Bindable var model: ApplicationsModel
    let app: InstalledApp
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                AppIcon(path: app.path, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).font(.title2)
                    Text("\(app.bundleID) · \(app.versionText)").font(.callout).foregroundStyle(.secondary)
                    Text(lastUsedLine).font(.callout).foregroundStyle(.secondary)
                    if let why = model.blocker(app) {
                        HStack {
                            Label(why, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            if model.isRunning(app) { Button("Quit \(app.name)") { model.quit(app) } }
                            if appModel.helper.state.isReady == false && app.needsHelper(userID: model.context?.home.userID ?? 0) {
                                Button("Open Setup") { appModel.showSetup = true }
                            }
                        }
                        .font(.callout)
                    }
                }
                Spacer()
                Toggle("Uninstall", isOn: Binding(get: { model.ticked.contains(app.path) }, set: { model.tick(app.path, $0) }))
                    .toggleStyle(.checkbox)
            }
            .padding(20)
            Divider()
            if let plan = model.plans[app.path] {
                PlanTable(model: model, plan: plan)
                if !plan.needsFullDiskAccess.isEmpty {
                    Label("Containers weren't searched: they need Full Disk Access.", systemImage: "lock")
                        .font(.caption).foregroundStyle(.secondary).padding(8)
                }
            } else {
                ProgressView("Finding related files…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    var lastUsedLine: String {
        guard let d = app.lastUsed else { return "No usage date from Spotlight" }
        return "Last opened \(d.formatted(.relative(presentation: .named)))"
    }
}

struct PlanTable: View {
    @Bindable var model: ApplicationsModel
    let plan: UninstallPlan
    @Environment(AppModel.self) private var appModel

    var rows: [Candidate] { [plan.appItem] + plan.related }

    var body: some View {
        Table(rows) {
            TableColumn("") { c in
                if c.ruleID == RelatedFileFinder.appRuleID {
                    Image(systemName: "checkmark.square.fill").foregroundStyle(.secondary).help("The app itself is always included")
                        .accessibilityLabel("The app itself is always included")
                } else {
                    Toggle("", isOn: Binding(get: { !model.unticked.contains(c.id) },
                                             set: { on in if on { model.unticked.remove(c.id) } else { model.unticked.insert(c.id) } }))
                        .labelsHidden()
                        .accessibilityLabel("Include \(c.name)")
                }
            }
            .width(24)
            TableColumn("Name") { c in
                HStack(spacing: 4) {
                    Text(c.name).lineLimit(1).help(c.name)
                    if c.viaHelper { AdminBadge(font: .caption2) }
                }
            }
            .width(min: 160, ideal: 240)
            TableColumn("Location") { c in PathText(path: (c.path as NSString).deletingLastPathComponent) }
            TableColumn("Goes to") { _ in DestinationLabel(action: .trash) }.width(70)
            TableColumn("Size") { c in
                Text(sizeString(c.allocatedBytes)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(80)
        }
        .contextMenu(forSelectionType: Candidate.ID.self) { ids in
            if let c = rows.first(where: { ids.contains($0.id) }) {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: c.path)]) }
            }
        }
        if !plan.kept.isEmpty || !plan.receipts.isEmpty {
            DisclosureGroup("Kept and other details (\(plan.kept.count + plan.receipts.count))") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plan.kept, id: \.path) { k in
                        HStack { PathText(path: k.path); Spacer(); Text(k.reason).font(.caption).foregroundStyle(.secondary) }
                    }
                    ForEach(plan.receipts, id: \.self) { r in
                        HStack {
                            Text("Package receipt \(r)").font(.callout)
                            Spacer()
                            Text(appModel.helper.state.isReady ? "Forgotten after the app is removed" : "Needs the admin helper")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }
}

/// The one confirmation before uninstalling (spec 007 §3.5, §4): count, size, destination, and
/// the items needing the administrator password by name.
struct UninstallConfirm: ViewModifier {
    @Binding var isPresented: Bool
    let model: ApplicationsModel

    func body(content: Content) -> some View {
        let plans = model.readyPlans
        let s = model.uninstallSummary
        let title = plans.count == 1 ? "Uninstall \(plans[0].app.name)?" : "Uninstall \(plans.count) apps?"
        content.alert(title, isPresented: $isPresented) {
            Button("Move \(sizeString(s.trashBytes)) to Trash") { model.uninstall(dryRun: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message(plans, s))
        }
    }

    func message(_ plans: [UninstallPlan], _ s: CleanupSummary) -> String {
        var lines = ["\(s.itemCount) items (\(plans.map(\.app.name).joined(separator: ", ")) and their related files, \(sizeString(s.trashBytes))) move to the Trash, where you can restore them."]
        let admin = model.uninstallAdminItems
        if !admin.isEmpty {
            let names = admin.prefix(12).map { "• " + $0.path }
            let more = admin.count > 12 ? ["…and \(admin.count - 12) more"] : []
            lines.append("\nWith your administrator password:\n" + (names + more).joined(separator: "\n") + "\n")
        }
        let receipts = plans.flatMap(\.receipts)
        if !receipts.isEmpty { lines.append("Package receipts forgotten: \(receipts.joined(separator: ", ")).") }
        lines.append("Every item is logged in Health › Run History.")
        return lines.joined(separator: " ")
    }
}

extension View {
    func uninstallConfirm(_ isPresented: Binding<Bool>, model: ApplicationsModel) -> some View {
        modifier(UninstallConfirm(isPresented: isPresented, model: model))
    }
}

// MARK: - Unused

struct UnusedTab: View {
    @Bindable var model: ApplicationsModel

    var body: some View {
        let split = UnusedApps.split(model.apps, days: model.unusedDays)
        VStack(spacing: 0) {
            HStack {
                Picker("Not opened in", selection: $model.unusedDays) {
                    ForEach(UnusedApps.thresholds, id: \.self) { Text("\($0) days").tag($0) }
                }
                .fixedSize()
                Spacer()
                Text("From Spotlight's last-opened date. This list never removes anything itself.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            Divider()
            if model.loadingApps && model.listing == nil {
                ProgressView("Looking for apps…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("Not opened in \(model.unusedDays) days (\(split.unused.count))") {
                        if split.unused.isEmpty { Text("None").foregroundStyle(.secondary) }
                        ForEach(split.unused) { UnusedRow(model: model, app: $0) }
                    }
                    Section("No usage date (\(split.noDate.count))") {
                        ForEach(split.noDate) { UnusedRow(model: model, app: $0) }
                    }
                }
            }
            FooterBar(summary: model.ticked.isEmpty ? "Tick apps to review them in the Uninstaller" : "\(model.ticked.count) apps ticked") {
                Button("Review in Uninstaller") {
                    model.focused = model.ticked.sorted().first ?? model.focused
                    model.tab = .uninstaller
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.ticked.isEmpty)
            }
        }
    }
}

struct UnusedRow: View {
    @Bindable var model: ApplicationsModel
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { model.ticked.contains(app.path) }, set: { model.tick(app.path, $0) }))
                .labelsHidden()
                .accessibilityLabel("Select \(app.name)")
            AppIcon(path: app.path, size: 24)
            Text(app.name)
            Spacer()
            Text(app.lastUsed.map { "Last opened \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Never seen by Spotlight")
                .font(.callout).foregroundStyle(.secondary)
            Text(sizeString(app.allocatedBytes)).monospacedDigit().foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
        }
    }
}

// MARK: - Leftovers

struct LeftoversTab: View {
    @Bindable var model: ApplicationsModel
    @Environment(AppModel.self) private var app
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            if model.scanningLeftovers {
                ProgressView("Looking for files of apps that are gone…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let groups = model.leftovers {
                if groups.isEmpty {
                    EmptyStateView(symbol: "checkmark.circle", message: "No leftovers of removed apps were found.") {
                        Button("Scan Again") { model.scanLeftovers() }
                    }
                } else {
                    List {
                        Section {
                            Label("These belong to apps that are no longer installed. Nothing is ticked: check each one before removing it.",
                                  systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                            if !model.leftoverNeedsFDA.isEmpty {
                                Label("Containers weren't searched: they need Full Disk Access.", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(groups) { g in LeftoverGroupRow(model: model, group: g) }
                    }
                }
            } else {
                EmptyStateView(symbol: "shippingbox", message: "Look for files left behind by apps you've removed.") {
                    Button("Scan") { model.scanLeftovers() }.buttonStyle(.borderedProminent)
                }
            }
            FooterBar(summary: model.leftoverSummary.line) {
                Button("Dry Run") { model.removeLeftovers(dryRun: true) }.disabled(model.leftoverSummary.itemCount == 0)
                Button(model.leftoverSummary.itemCount == 0 ? "Remove" : "Remove \(sizeString(model.leftoverSummary.totalBytes))") { showConfirm = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.leftoverSummary.itemCount == 0)
            }
        }
        .cleanConfirm($showConfirm, summary: model.leftoverSummary,
                      adminItems: model.leftoverSelection.selected(from: (model.leftovers ?? []).flatMap(\.items)).filter(\.viaHelper)) {
            model.removeLeftovers(dryRun: false)
        }
    }
}

struct LeftoverGroupRow: View {
    @Bindable var model: ApplicationsModel
    let group: LeftoverGroup
    @Environment(AppModel.self) private var app

    var body: some View {
        DisclosureGroup {
            ForEach(group.items) { c in
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(get: { model.leftoverSelection.contains(c) }, set: { model.leftoverSelection.set(c, $0) }))
                        .labelsHidden()
                        .accessibilityLabel("Select \(c.name)")
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(c.name).lineLimit(1)
                            if c.viaHelper { AdminBadge(font: .caption2) }
                        }
                        PathText(path: (c.path as NSString).deletingLastPathComponent)
                    }
                    Spacer()
                    RiskBadge(risk: c.risk)
                    Text(sizeString(c.allocatedBytes)).monospacedDigit().foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                }
                .contextMenu {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: c.path)]) }
                    Button("Ignore") { app.ignore(.init(kind: .path, value: c.path)) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                TriStateBox(state: model.leftoverSelection.state(of: group.items)) {
                    model.leftoverSelection.setGroup(group.items, model.leftoverSelection.state(of: group.items) != .all)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.ownerBundleID).font(.body.monospaced())
                    if group.vendorHasInstalledApp {
                        Text("Another app from this developer is installed; some of these may be shared.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(group.items.count) items").foregroundStyle(.secondary)
                Text(sizeString(group.totalBytes)).monospacedDigit().foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
            }
        }
    }
}

// MARK: - Installers

struct InstallersTab: View {
    @Bindable var session: ScanSession
    @State private var showConfirm = false

    var body: some View {
        switch session.phase {
        case .idle, .scanning:
            ProgressView("Looking for installer files…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .running:
            ProgressView("Moving to the Trash…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done(let dry):
            if let run = session.lastRun { RunResultView(run: run, dryRun: dry) { session.finish(); session.scan() } }
        case .results:
            if let result = session.report?.results.first {
                RuleDetail(session: session, result: result)
            }
            FooterBar(summary: session.summary.line) {
                Button("Dry Run") { session.run(dryRun: true) }.disabled(session.summary.itemCount == 0)
                Button(session.summary.itemCount == 0 ? "Remove" : "Remove \(sizeString(session.summary.totalBytes))") { showConfirm = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.summary.itemCount == 0)
            }
            .cleanConfirm($showConfirm, summary: session.summary) { session.run(dryRun: false) }
        }
    }
}

// MARK: - Updates

struct UpdatesTab: View {
    @Bindable var model: ApplicationsModel
    @State private var showUpToDate = false
    @State private var showNotChecked = false

    var body: some View {
        let available = model.updates.filter { $0.state == .updateAvailable }
        let upToDate = model.updates.filter { $0.state == .upToDate }
        let appStore = model.updates.filter { $0.state == .appStore }
        let notChecked = model.updates.filter { if case .notChecked = $0.state { true } else { false } }
        VStack(spacing: 0) {
            List {
                Section("macOS") { MacOSRow(model: model) }
                Section(available.isEmpty ? "Apps" : "Updates available (\(available.count))") {
                    if model.checkingUpdates && model.updates.isEmpty {
                        HStack { ProgressView().controlSize(.small); Text("Checking…") }
                    } else if available.isEmpty {
                        Text(model.updates.isEmpty ? "Not checked yet." : "Every app with an update source is up to date.").foregroundStyle(.secondary)
                    }
                    ForEach(available) { UpdateRow(model: model, status: $0) }
                }
                if !appStore.isEmpty {
                    Section("Updated by the App Store (\(appStore.count))") { ForEach(appStore) { UpdateRow(model: model, status: $0) } }
                }
                if !upToDate.isEmpty {
                    Section(isExpanded: $showUpToDate) { ForEach(upToDate) { UpdateRow(model: model, status: $0) } } header: {
                        Text("Up to date (\(upToDate.count))")
                    }
                }
                if !notChecked.isEmpty {
                    Section(isExpanded: $showNotChecked) { ForEach(notChecked) { UpdateRow(model: model, status: $0) } } header: {
                        Text("Not checked (\(notChecked.count))")
                    }
                }
            }
            .listStyle(.sidebar)
            FooterBar(summary: footer) {
                Button(model.checkingUpdates ? "Checking…" : "Check Now") { model.checkUpdates() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.checkingUpdates)
            }
        }
    }

    var footer: String {
        guard let d = model.updatesChecked else { return "TidyMyMac only checks. Each app installs its own updates." }
        return "Checked \(d.formatted(.relative(presentation: .named))) · TidyMyMac never installs anything"
    }
}

struct UpdateRow: View {
    let model: ApplicationsModel
    let status: UpdateStatus

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(path: status.appPath, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.name)
                Group {
                    switch status.state {
                    case .updateAvailable: Text("\(status.installedVersion) → \(status.availableVersion ?? "?")")
                    case .upToDate: Text(status.installedVersion)
                    case .appStore: Text("\(status.installedVersion) · updated by the App Store")
                    case .notChecked(let why): Text("\(status.installedVersion) · \(why)")
                    }
                }
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                if status.state == .updateAvailable, let command = status.brewUpgradeCommand {
                    HStack(spacing: 4) {
                        Text("Update with").foregroundStyle(.secondary)
                        Text(command).font(.callout.monospaced()).textSelection(.enabled)
                        Button { model.copy(command) } label: { Image(systemName: "doc.on.doc") }
                            .accessibilityLabel("Copy command")
                            .buttonStyle(.borderless).help("Copy the command. TidyMyMac never runs it.")
                    }
                    .font(.callout)
                }
            }
            Spacer()
            if status.source != .none {
                Text(status.source.badge).font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            if let notes = status.releaseNotes, let url = URL(string: notes), url.scheme == "https" {
                Link("Release Notes", destination: url).font(.callout)
            }
            if status.state == .updateAvailable || status.state == .appStore {
                Button(status.state == .appStore ? "Open App Store" : "Open App") { model.open(status) }
            }
        }
        .padding(.vertical, 2)
    }
}

struct MacOSRow: View {
    let model: ApplicationsModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "apple.logo").font(.title2).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("macOS and Apple software")
                Text(line).font(.callout).foregroundStyle(.secondary)
                if let e = model.macOSError { Text(e).font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            Button(model.checkingMacOS ? "Checking…" : "Check Apple Updates") { model.checkAppleUpdates() }
                .disabled(model.checkingMacOS)
                .help("Runs softwareupdate --list (can take a minute). Nothing is installed.")
            Button("Open Software Update") { model.openSoftwareUpdate() }
        }
    }

    var line: String {
        if let list = model.macOSList { return list.isEmpty ? "No updates (just checked)" : list.map(\.title).joined(separator: ", ") }
        switch model.macOSPassive {
        case .unknown: return "Unknown"
        case .updates(let u): return u.isEmpty ? "No updates waiting" : u.map(\.title).joined(separator: ", ")
        }
    }
}
