import AppKit
import DiskAnalysis
import RuleEngine
import SwiftUI

/// Declutter (spec 007 §2): Large & Old · Duplicates · Downloads. Personal files: nothing is
/// ticked for you except duplicate copies, and everything goes to the Trash.
struct DeclutterView: View {
    @Environment(AppModel.self) private var app
    @State private var showConfirm = false

    var model: ClutterModel { app.clutter }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            switch model.phase {
            case .running:
                ProgressView("Moving to the Trash…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done(let dry):
                if let run = model.lastRun { RunResultView(run: run, dryRun: dry) { model.finish() } }
            case .browsing:
                Group {
                    switch model.tab {
                    case .largeOld: LargeOldTab(model: model)
                    case .duplicates: DuplicatesTab(model: model)
                    case .downloads: DownloadsTab(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                FooterBar(summary: model.footerLine) {
                    Button("Dry Run") { model.remove(dryRun: true) }
                        .help("List exactly what would be moved, without changing anything")
                        .disabled(model.picks.isEmpty)
                    Button("Move to Trash…") { showConfirm = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.picks.isEmpty)
                }
                .trashConfirm($showConfirm, count: model.picks.count, bytes: model.pickedBytes) { model.remove(dryRun: false) }
            }
        }
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Tab", selection: $model.tab) {
                    ForEach(ClutterModel.Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(model.phase != .browsing)
            }
            ToolbarItem { ScopeMenu(model: model) }
            ToolbarItem {
                if model.isScanning {
                    Button { model.stop() } label: { Label("Stop", systemImage: "stop.circle") }
                } else {
                    Button { model.rescan() } label: { Label("Scan Again", systemImage: "arrow.clockwise") }
                        .help("Look again (⌘R)")
                        .keyboardShortcut("r")
                        .disabled(model.phase != .browsing)
                }
            }
        }
        .onAppear { model.onTab() }
        .onChange(of: model.tab) { _, _ in model.onTab() }
        .alert("Something went wrong", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") {}
        } message: { Text(model.error ?? "") }
    }

    var subtitle: String {
        switch model.tab {
        case .largeOld: return model.largeFiles == nil ? "" : "\(model.visibleLarge.count) files · \(sizeString(model.visibleLarge.reduce(0) { $0 + $1.allocatedBytes }))"
        case .duplicates:
            guard let g = model.groups else { return "" }
            return "\(g.count) sets · \(sizeString(g.reduce(0) { $0 + $1.reclaimableBytes })) you can free"
        case .downloads: return model.downloads == nil ? "" : "\(model.visibleDownloads.count) items"
        }
    }
}

/// Where Declutter looks: the six default folders plus Add Folder… (spec 014 §3).
struct ScopeMenu: View {
    @Bindable var model: ClutterModel
    @Environment(AppModel.self) private var app

    var body: some View {
        Menu {
            Section("Looking in") {
                Text("Desktop, Documents, Downloads, Pictures, Movies, Music")
                ForEach(model.extraFolders, id: \.self) { f in
                    Button("Stop Looking in \((f as NSString).lastPathComponent)") { model.removeFolder(f) }
                }
            }
            Button("Add Folder…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = "Add"
                panel.message = "Choose a folder or an external volume to include. ~/Library, iCloud Drive and hidden files are always skipped."
                if panel.runModal() == .OK, let url = panel.url { model.addFolder(url.path) }
            }
        } label: {
            Label("Folders", systemImage: "folder.badge.plus")
        }
        .help("Choose where Declutter looks")
        .disabled(model.phase != .browsing || model.isScanning)
    }
}

/// Shared row actions: Show in Finder and Ignore.
struct ClutterContextMenu: View {
    let path: String
    let model: ClutterModel

    var body: some View {
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        Button("Quick Look") { QuickLook.show(path) }
        Divider()
        Button("Ignore") { model.ignore(path) }
    }
}

/// Opens Quick Look for a file (Space on a row, build spec §6.12) through Finder's preview.
enum QuickLook {
    static func show(_ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        p.arguments = ["-p", path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}

struct ClutterScanningView: View {
    let title: String
    var detail: String?
    var body: some View {
        VStack(spacing: 8) {
            ProgressView(title)
            if let detail { Text(detail).font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Large & Old

struct LargeOldTab: View {
    @Bindable var model: ClutterModel
    @State private var tableSelection: Set<String> = []

    static let sizes: [(String, Int64)] = [("50 MB", 50_000_000), ("100 MB", 100_000_000), ("500 MB", 500_000_000), ("1 GB", 1_000_000_000)]
    static let ages: [(String, Int?)] = [("Any age", nil), ("6 months", 182), ("1 year", 365), ("2 years", 730)]

    var body: some View {
        if model.largeFiles == nil {
            ClutterScanningView(title: "Looking for large and old files…")
        } else {
            VStack(spacing: 0) {
                filterBar
                Divider()
                if model.visibleLarge.isEmpty {
                    EmptyStateView(symbol: "doc.badge.clock", message: "No files match these filters.")
                } else {
                    table
                }
            }
        }
    }

    var filterBar: some View {
        HStack(spacing: 16) {
            Picker("At least", selection: $model.largeFilter.minimumSize) {
                ForEach(Self.sizes, id: \.1) { Text($0.0).tag($0.1) }
            }
            .fixedSize()
            Picker("Not modified in", selection: $model.largeFilter.olderThanDays) {
                ForEach(Self.ages, id: \.0) { Text($0.0).tag($0.1) }
            }
            .fixedSize()
            Picker("Show", selection: $model.largeFilter.match) {
                ForEach(LargeOldFilter.Match.allCases) { Text($0.title).tag($0) }
            }
            .fixedSize()
            .disabled(model.largeFilter.olderThanDays == nil)
            Menu("Kinds") {
                ForEach(FileKind.allCases) { k in
                    Toggle(k.title, isOn: Binding(get: { model.largeFilter.kinds.contains(k) },
                                                  set: { if $0 { model.largeFilter.kinds.insert(k) } else { model.largeFilter.kinds.remove(k) } }))
                }
            }
            .fixedSize()
            Spacer()
            let shown = model.visibleLarge.map(\.path)
            CheckAllButtons(canCheckAll: !shown.allSatisfy(model.largeSelection.contains),
                            canCheckNone: shown.contains(where: model.largeSelection.contains),
                            checkAll: { model.largeSelection.formUnion(shown) },
                            checkNone: { model.largeSelection.subtract(shown) })
        }
        .controlSize(.small)
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    /// Rows in the order of the clicked column header; largest first until one is clicked.
    var rows: [FileEntry] {
        model.largeSortOrder.isEmpty ? model.visibleLarge : model.visibleLarge.sorted(using: model.largeSortOrder)
    }

    var table: some View {
        Table(rows, selection: $tableSelection, sortOrder: $model.largeSortOrder) {
            TableColumn("") { f in
                Toggle("", isOn: Binding(get: { model.largeSelection.contains(f.path) },
                                         set: { if $0 { model.largeSelection.insert(f.path) } else { model.largeSelection.remove(f.path) } }))
                    .labelsHidden()
                    .accessibilityLabel("Select \(f.name)")
            }
            .width(24)
            TableColumn("Name", value: \.name) { f in
                HStack(spacing: 6) {
                    AppIcon(path: f.path, size: 16)
                    Text(f.name).lineLimit(1).help(f.name)
                }
            }
            .width(min: 160, ideal: 240)
            TableColumn("Location", value: \.folder) { f in PathText(path: f.folder) }
            TableColumn("Kind", value: \.kindTitle) { f in Text(f.kindTitle).foregroundStyle(.secondary) }.width(80)
            TableColumn("Modified", value: \.modified) { f in Text(f.modified, format: .dateTime.year().month().day()).foregroundStyle(.secondary) }.width(90)
            TableColumn("Size", value: \.allocatedBytes) { f in
                Text(sizeString(f.allocatedBytes)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(80)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let p = ids.first { ClutterContextMenu(path: p, model: model) }
        }
        .onKeyPress(.space) {
            if let p = tableSelection.first { QuickLook.show(p) }
            return .handled
        }
        .onKeyPress(keys: [.delete]) { press in
            // ⌘⌫ ticks the highlighted rows (build spec §6.12); it never removes anything itself.
            guard press.modifiers.contains(.command) else { return .ignored }
            model.largeSelection.formUnion(tableSelection)
            return .handled
        }
    }
}

// MARK: - Duplicates

struct DuplicatesTab: View {
    @Bindable var model: ClutterModel

    var body: some View {
        if let groups = model.groups {
            VStack(spacing: 0) {
                HStack {
                    Picker("Select", selection: $model.keepRule) {
                        ForEach(KeepRule.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .onChange(of: model.keepRule) { _, _ in model.applyKeepRule() }
                    Spacer()
                    Text("Keeps the copy outside Downloads and Desktop first. One copy always stays.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .controlSize(.small)
                .padding(.horizontal, 16).padding(.vertical, 8)
                Divider()
                if groups.isEmpty {
                    EmptyStateView(symbol: "doc.on.doc", message: "No duplicates of 1 MB or more in the folders Declutter looks in.")
                } else {
                    List {
                        ForEach(groups) { g in
                            Section {
                                ForEach(g.files) { f in DuplicateRow(model: model, group: g, file: f) }
                            } header: {
                                HStack {
                                    Text(g.name).font(.headline)
                                    Text("\(g.files.count) copies · \(sizeString(g.files.first?.entry.allocatedBytes ?? 0)) each")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    let freed = model.duplicateSelection.freedBytes([g])
                                    Text(freed == 0 ? "frees nothing" : "frees \(sizeString(freed))")
                                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        } else {
            let p = model.hashProgress
            ClutterScanningView(title: "Looking for duplicates…",
                         detail: p.map { $0.toHash == 0 ? "Listing files" : "Compared \($0.hashed.formatted()) of \($0.toHash.formatted()) files of matching size" })
        }
    }
}

struct DuplicateRow: View {
    @Bindable var model: ClutterModel
    let group: DuplicateGroup
    let file: DuplicateFile

    var body: some View {
        let ticked = model.duplicateSelection.contains(file)
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { ticked }, set: { model.tick(file, in: group, $0) }))
                .labelsHidden()
                .disabled(!model.duplicateSelection.canTick(file, in: group))
                .help(model.duplicateSelection.canTick(file, in: group) ? "" : "One copy always stays")
                .accessibilityLabel("Select \(file.entry.name)")
            AppIcon(path: file.path, size: 16)
            PathText(path: file.path)
            Spacer()
            if group.sharesSpace(file) {
                Label("Shares space, frees ~0 KB", systemImage: "square.on.square.dashed")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("An APFS clone: it shares its data with another copy, so removing it frees almost nothing")
            }
            if !ticked { Text("Keep").font(.caption).foregroundStyle(.green) }
            Text(file.entry.created, format: .dateTime.year().month().day())
                .font(.caption).foregroundStyle(.secondary).help("Created")
        }
        .contextMenu { ClutterContextMenu(path: file.path, model: model) }
    }
}

// MARK: - Downloads

struct DownloadsTab: View {
    @Bindable var model: ClutterModel
    @State private var tableSelection: Set<String> = []

    static let ages: [(String, Int?)] = [("Older than 30 days", 30), ("Older than 90 days", 90), ("Older than a year", 365), ("Everything", nil)]

    var body: some View {
        if model.downloads == nil {
            ClutterScanningView(title: "Looking through Downloads…")
        } else {
            VStack(spacing: 0) {
                HStack {
                    Picker("Show", selection: $model.downloadsOlderThan) {
                        ForEach(Self.ages, id: \.0) { Text($0.0).tag($0.1) }
                    }
                    .fixedSize()
                    Spacer()
                    let dupes = model.visibleDownloads.filter { !$0.alsoElsewhere.isEmpty }.count
                    if dupes > 0 { Label("\(dupes) also elsewhere", systemImage: "doc.on.doc").font(.caption).foregroundStyle(.secondary) }
                    let shown = model.visibleDownloads.map(\.path)
                    CheckAllButtons(canCheckAll: !shown.allSatisfy(model.downloadsSelection.contains),
                                    canCheckNone: shown.contains(where: model.downloadsSelection.contains),
                                    checkAll: { model.downloadsSelection.formUnion(shown) },
                                    checkNone: { model.downloadsSelection.subtract(shown) })
                }
                .controlSize(.small)
                .padding(.horizontal, 16).padding(.vertical, 8)
                Divider()
                if model.visibleDownloads.isEmpty {
                    EmptyStateView(symbol: "arrow.down.circle", message: "Nothing in Downloads matches this filter.")
                } else {
                    table
                }
            }
        }
    }

    /// Rows in the order of the clicked column header; oldest first until one is clicked.
    var rows: [DownloadItem] {
        model.downloadsSortOrder.isEmpty ? model.visibleDownloads : model.visibleDownloads.sorted(using: model.downloadsSortOrder)
    }

    var table: some View {
        Table(rows, selection: $tableSelection, sortOrder: $model.downloadsSortOrder) {
            TableColumn("") { d in
                Toggle("", isOn: Binding(get: { model.downloadsSelection.contains(d.path) },
                                         set: { if $0 { model.downloadsSelection.insert(d.path) } else { model.downloadsSelection.remove(d.path) } }))
                    .labelsHidden()
                    .accessibilityLabel("Select \(d.name)")
            }
            .width(24)
            TableColumn("Name", value: \.name) { d in
                HStack(spacing: 6) {
                    AppIcon(path: d.path, size: 16)
                    Text(d.name).lineLimit(1).help(d.name)
                    if !d.alsoElsewhere.isEmpty {
                        Label("Also elsewhere", systemImage: "doc.on.doc")
                            .font(.caption).foregroundStyle(Color.accentColor)
                            .help("The same file (same contents) is also at:\n" + d.alsoElsewhere.joined(separator: "\n"))
                    }
                }
            }
            .width(min: 200, ideal: 320)
            TableColumn("From", value: \.sourceSortKey) { d in Text(d.sourceHost ?? "—").foregroundStyle(.secondary).lineLimit(1) }.width(min: 80, ideal: 140)
            TableColumn("Added", value: \.dateAdded) { d in Text(d.dateAdded, format: .dateTime.year().month().day()).foregroundStyle(.secondary) }.width(90)
            TableColumn("Size", value: \.allocatedBytes) { d in
                Text(sizeString(d.allocatedBytes)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(80)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let p = ids.first { ClutterContextMenu(path: p, model: model) }
        }
        .onKeyPress(.space) {
            if let p = tableSelection.first { QuickLook.show(p) }
            return .handled
        }
        .onKeyPress(keys: [.delete]) { press in
            // ⌘⌫ ticks the highlighted rows (build spec §6.12); it never removes anything itself.
            guard press.modifiers.contains(.command) else { return .ignored }
            model.downloadsSelection.formUnion(tableSelection)
            return .handled
        }
    }
}

/// Sort keys for the Large & Old and Downloads tables.
extension FileEntry {
    var kindTitle: String { FileKind.of(path).title }
}

extension DownloadItem {
    /// Unknown sources sort last.
    var sourceSortKey: String { sourceHost ?? "\u{10FFFF}" }
}
