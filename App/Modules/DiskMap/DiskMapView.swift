import AppKit
import DiskAnalysis
import SwiftUI

/// Disk Map (spec 007 §2, build spec §6.8): breadcrumb, disk/folder picker, a treemap two
/// levels deep and a size-ranked list with ticks. Removal goes to the Trash only.
struct DiskMapView: View {
    @Environment(AppModel.self) private var app
    @State private var showConfirm = false

    var model: DiskMapModel { app.diskMap }

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .running:
                ProgressView("Moving to the Trash…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done(let dry):
                if let run = model.lastRun { RunResultView(run: run, dryRun: dry) { model.finish() } }
            case .browsing:
                content
                FooterBar(summary: model.footerLine) {
                    Button("Dry Run") { model.remove(dryRun: true) }
                        .help("List exactly what would be moved, without changing anything")
                        .disabled(model.pickedNodes.isEmpty)
                    Button("Move to Trash…") { showConfirm = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.pickedNodes.isEmpty)
                }
                .trashConfirm($showConfirm, count: model.pickedNodes.count, bytes: model.pickedBytes) { model.remove(dryRun: false) }
            }
        }
        .navigationSubtitle(model.root.map { "\(sizeString($0.allocatedBytes)) in \(model.target?.name ?? "")" } ?? "")
        .toolbar {
            ToolbarItem { TargetMenu(model: model) }
            ToolbarItem {
                if model.scanning {
                    Button { model.stop() } label: { Label("Stop", systemImage: "stop.circle") }
                } else {
                    Button { model.scan() } label: { Label("Scan Again", systemImage: "arrow.clockwise") }
                        .help("Measure again (⌘R)")
                        .keyboardShortcut("r")
                        .disabled(model.phase != .browsing || model.target == nil)
                }
            }
        }
        .onAppear { model.start() }
        .alert("Something went wrong", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") {}
        } message: { Text(model.error ?? "") }
    }

    @ViewBuilder var content: some View {
        if model.scanning || model.root == nil {
            VStack(spacing: 8) {
                ProgressView("Measuring \(model.target?.name ?? "")…")
                if let p = model.progress {
                    Text("\(sizeString(p.bytes)) in \(p.items.formatted()) items").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let current = model.current {
            let _ = model.revision
            VStack(spacing: 0) {
                Breadcrumb(model: model, node: current)
                Divider()
                HStack(spacing: 0) {
                    TreemapView(model: model, node: current)
                        .padding(8)
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    SpaceList(model: model, node: current)
                        .frame(width: 320)
                }
            }
        }
    }
}

/// Home, the startup disk, each mounted volume, Choose Folder… (build spec §6.8).
struct TargetMenu: View {
    @Bindable var model: DiskMapModel

    var body: some View {
        Menu {
            ForEach(model.targets) { t in
                Button { model.choose(t) } label: { Label(t.name, systemImage: t.symbol) }
            }
            Divider()
            Button("Choose Folder…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = "Measure"
                if panel.runModal() == .OK, let url = panel.url { model.chooseFolder(url.path) }
            }
        } label: {
            Label(model.target?.name ?? "Choose", systemImage: model.target?.symbol ?? "internaldrive")
        }
        .help("Choose what to measure")
        .disabled(model.scanning || model.phase != .browsing)
    }
}

struct Breadcrumb: View {
    let model: DiskMapModel
    let node: SpaceNode

    var body: some View {
        HStack(spacing: 4) {
            Button { model.up() } label: { Image(systemName: "chevron.backward") }
                .buttonStyle(.borderless)
                .disabled(node.parent == nil)
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("Up one level (⌘↑)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(node.ancestry.enumerated()), id: \.element.id) { i, n in
                        if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                        Button(n.name) { model.current = n; model.focused = nil }
                            .buttonStyle(.borderless)
                            .fontWeight(n === node ? .semibold : .regular)
                            .foregroundStyle(n === node ? .primary : .secondary)
                    }
                }
            }
            Spacer()
            Text(sizeString(node.allocatedBytes)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

// MARK: - Colours

/// Folders are coloured by position, files by kind, unreadable space grey; the accent marks
/// the selection (build spec §6.8, style guide §3).
enum LensColor {
    static let folders: [Color] = [.teal, .blue, .indigo, .purple, .pink, .orange, .yellow, .green, .mint, .cyan, .brown]

    static func of(_ node: SpaceNode, index: Int) -> Color {
        switch node.kind {
        case .folder: folders[index % folders.count]
        case .package: .purple
        case .notReadable: .gray
        case .smallFiles: .gray.opacity(0.6)
        case .file:
            switch FileKind.of(node.path) {
            case .movies: .red
            case .music: .pink
            case .pictures: .orange
            case .archives, .diskImages: .brown
            case .documents: .blue
            case .apps: .purple
            case .other: .secondary
            }
        }
    }
}

// MARK: - Treemap

struct TreemapView: View {
    let model: DiskMapModel
    let node: SpaceNode

    var body: some View {
        GeometryReader { geo in
            let kids = node.children.filter { $0.allocatedBytes > 0 }
            let rects = Treemap.layout(kids.map { Double($0.allocatedBytes) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(kids.indices), id: \.self) { i in
                    TreemapBlock(model: model, node: kids[i], rect: rects[i], color: LensColor.of(kids[i], index: i), depth: 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Treemap of \(node.name)")
    }
}

struct TreemapBlock: View {
    let model: DiskMapModel
    let node: SpaceNode
    let rect: CGRect
    let color: Color
    let depth: Int

    static let header: CGFloat = 16

    var body: some View {
        let focused = model.focused == node.id
        let picked = model.isPicked(node)
        let w = max(0, rect.width - 1), h = max(0, rect.height - 1)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: depth == 0 ? 4 : 2)
                .fill(color.opacity(depth == 0 ? 0.35 : 0.55))
            if picked {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.35))
            }
            if depth == 0, node.kind == .folder, w > 40, h > 36 {
                // Second level inside the block.
                let inner = CGRect(x: 2, y: Self.header, width: w - 4, height: h - Self.header - 2)
                let kids = node.children.filter { $0.allocatedBytes > 0 }
                let rects = Treemap.layout(kids.map { Double($0.allocatedBytes) }, in: inner)
                ForEach(Array(kids.indices), id: \.self) { i in
                    if rects[i].width * rects[i].height >= 24 {
                        TreemapBlock(model: model, node: kids[i], rect: rects[i],
                                     color: kids[i].kind == .folder ? color : LensColor.of(kids[i], index: i), depth: 1)
                    }
                }
            }
            if w > 50, h > 14 {
                Text(label)
                    .font(.caption2.weight(depth == 0 ? .semibold : .regular))
                    .lineLimit(1)
                    .padding(.horizontal, 4).padding(.top, 2)
                    .frame(maxWidth: w, alignment: .leading)
                    .allowsHitTesting(false)
            }
            RoundedRectangle(cornerRadius: depth == 0 ? 4 : 2)
                .strokeBorder(focused ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: focused ? 2 : 0.5)
                .allowsHitTesting(false)
        }
        .frame(width: w, height: h)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.open(node) }
        .onTapGesture { model.focused = node.id }
        .help("\(node.name): \(sizeString(node.allocatedBytes))")
        .offset(x: rect.minX, y: rect.minY)
    }

    var label: String { node.kind == .folder || depth == 0 ? "\(node.name)  \(sizeString(node.allocatedBytes))" : node.name }
}

// MARK: - List

struct SpaceList: View {
    @Bindable var model: DiskMapModel
    let node: SpaceNode

    var body: some View {
        List(selection: $model.focused) {
            ForEach(Array(node.children.enumerated()), id: \.element.id) { i, c in
                SpaceRow(model: model, node: c, parentBytes: node.allocatedBytes, color: LensColor.of(c, index: i)).tag(c.id)
            }
        }
        .onKeyPress(.space) {
            if let f = model.focused, let n = node.children.first(where: { $0.id == f }), n.isItem { QuickLook.show(n.path) }
            return .handled
        }
        .onKeyPress(keys: [.delete]) { press in
            // ⌘⌫ ticks the highlighted row (build spec §6.12); it never removes anything itself.
            guard press.modifiers.contains(.command), let f = model.focused,
                  let n = node.children.first(where: { $0.id == f }) else { return .ignored }
            model.toggle(n, true)
            return .handled
        }
    }
}

struct SpaceRow: View {
    @Bindable var model: DiskMapModel
    let node: SpaceNode
    let parentBytes: Int64
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            if model.canPick(node) {
                Toggle("", isOn: Binding(get: { model.isPicked(node) }, set: { model.toggle(node, $0) }))
                    .labelsHidden()
                    .disabled(model.isPicked(node) && !model.selection.contains(node.path))
                    .accessibilityLabel("Select \(node.name)")
            } else {
                Image(systemName: node.isItem ? "lock" : "circle.dashed")
                    .foregroundStyle(.tertiary).frame(width: 16)
                    .help(node.isItem ? "Protected: TidyMyMac never removes this" : "")
            }
            RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.6)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).lineLimit(1).truncationMode(.middle).help(node.isItem ? node.path : explanation)
                Capsule().fill(color.opacity(0.5))
                    .frame(width: 140 * CGFloat(parentBytes > 0 ? Double(node.allocatedBytes) / Double(parentBytes) : 0), height: 3)
            }
            Spacer(minLength: 4)
            Text(sizeString(node.allocatedBytes)).font(.callout.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
            if node.canOpen {
                Button { model.open(node) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
                    .help("Open \(node.name)")
            } else {
                Color.clear.frame(width: 14)
            }
        }
        .contextMenu {
            if node.isItem {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)]) }
                Button("Quick Look") { QuickLook.show(node.path) }
            }
            if node.canOpen { Button("Open") { model.open(node) } }
        }
    }

    var explanation: String {
        switch node.kind {
        case .notReadable: "Space the scan couldn't read: protected folders, other users, snapshots and system volumes"
        case .smallFiles: "Smaller files in this folder, shown together"
        default: node.path
        }
    }
}
