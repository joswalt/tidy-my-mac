import DiskAnalysis
import Foundation
import Observation
import RuleEngine
import RunLog
import SafetyFloor

/// State for Space Lens (build spec §6.8): one scan per target, cached for the session only.
@MainActor @Observable
final class SpaceLensModel {
    enum Phase: Equatable {
        case browsing, running
        case done(dryRun: Bool)
    }

    struct Target: Hashable, Identifiable {
        let name: String
        let path: String
        let symbol: String
        var id: String { path }
    }

    weak var app: AppModel?
    var target: Target?
    var phase: Phase = .browsing
    var lastRun: CleanupEngine.Run?
    var error: String?

    var root: SpaceNode?
    var current: SpaceNode?
    var scanning = false
    var progress: SpaceScanner.Progress?
    /// The highlighted block (treemap and list stay in step).
    var focused: String?
    /// Ticked items, by path.
    var selection: Set<String> = []
    /// Bumped when the tree changes in place (after removal), so views redraw.
    var revision = 0
    /// Session cache: one tree per target.
    private var trees: [String: SpaceNode] = [:]
    private var cancel = CancelFlag()

    var context: CleanupContext? { app?.context }
    var scanner: SpaceScanner? { context.map { SpaceScanner(floor: $0.floor) } }

    /// Home, the startup disk, each mounted volume (plus a chosen folder, added when picked).
    var targets: [Target] {
        guard let home = context?.home else { return [] }
        var out = [Target(name: "Home", path: home.path, symbol: "house")]
        for v in Volumes.mounted() {
            out.append(Target(name: v.name, path: v.path, symbol: v.path == "/" ? "internaldrive" : "externaldrive"))
        }
        return out
    }

    func start() {
        guard target == nil, let first = targets.first else { return }
        choose(first)
    }

    func choose(_ t: Target) {
        target = t
        selection = []
        focused = nil
        if let cached = trees[t.path] {
            root = cached
            current = cached
        } else {
            scan()
        }
    }

    func chooseFolder(_ path: String) {
        choose(Target(name: (path as NSString).lastPathComponent, path: path, symbol: "folder"))
    }

    func scan() {
        guard let target, let scanner, !scanning else { return }
        scanning = true
        root = nil
        current = nil
        progress = nil
        selection = []
        let flag = cancel
        let path = target.path
        Task {
            let tree = await Task.detached {
                scanner.scan(path, progress: { p in Task { @MainActor in self.progress = p } }, isCancelled: { flag.isSet })
            }.value
            scanning = false
            guard !flag.isSet else { return }
            if let tree {
                trees[path] = tree
                root = tree
                current = tree
            } else {
                error = "\(path) couldn't be read."
            }
        }
    }

    func stop() {
        cancel.set()
        cancel = CancelFlag()
    }

    func open(_ node: SpaceNode) {
        guard node.canOpen else { return }
        current = node
        focused = nil
    }

    func up() {
        if let p = current?.parent { current = p }
    }

    func canPick(_ node: SpaceNode) -> Bool { scanner?.canPick(node) ?? false }

    func isPicked(_ node: SpaceNode) -> Bool {
        selection.contains(node.path) || node.ancestry.dropLast().contains { selection.contains($0.path) }
    }

    func toggle(_ node: SpaceNode, _ on: Bool) {
        guard canPick(node) else { return }
        if on {
            // Picking a folder covers everything inside it.
            selection = selection.filter { !PathNormalizer.isInside($0, node.path) }
            selection.insert(node.path)
        } else {
            selection.remove(node.path)
        }
    }

    var pickedNodes: [SpaceNode] {
        guard let root else { return [] }
        return selection.compactMap { root.find($0) }
    }

    var pickedBytes: Int64 { pickedNodes.reduce(0) { $0 + $1.allocatedBytes } }

    var footerLine: String {
        let n = pickedNodes
        guard !n.isEmpty else { return "Nothing selected" }
        return "\(n.count.formatted()) \(n.count == 1 ? "item" : "items") · \(sizeString(pickedBytes)) to Trash"
    }

    func remove(dryRun: Bool) {
        guard let ctx = context, let root else { return }
        let nodes = pickedNodes
        guard !nodes.isEmpty else { return }
        let scanRoot = root.path
        let items = nodes.compactMap { n in n.identity.map { (n.path, $0, n.allocatedBytes) } }
        phase = .running
        Task {
            do {
                let run = try await Task.detached { () throws -> CleanupEngine.Run in
                    let picks = items.map { path, identity, bytes in
                        ManualPick(path: path, root: SpaceScanner.containmentRoot(for: path, scanRoot: scanRoot) ?? (path as NSString).deletingLastPathComponent,
                                   identity: identity, allocatedBytes: bytes)
                    }
                    return try ManualRemover(context: ctx).run(picks, module: "spaceLens", dryRun: dryRun)
                }.value
                lastRun = run
                if !dryRun {
                    let done = Set(run.outcome.done.map(\.path))
                    root.prune(done)
                    selection.subtract(done)
                    if let c = current, root.find(c.path) !== c { current = root }
                    revision += 1
                }
                phase = .done(dryRun: dryRun)
            } catch {
                self.error = "\(error)"
                phase = .browsing
            }
            app?.reloadRuns()
        }
    }

    func finish() { phase = .browsing }
}
