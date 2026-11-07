import Foundation
import SafetyFloor
import UniformTypeIdentifiers

/// One item a rule found, ready for the review screen.
public struct Candidate: Hashable, Sendable, Identifiable {
    public let ruleID: String
    /// Real path of the item (never a symlink).
    public let path: String
    /// Real path of the concrete root the item was found under (for containment re-checks).
    public let root: String
    public let identity: ItemIdentity
    public let isDirectory: Bool
    public let allocatedBytes: Int64
    public let newestModification: Date
    public let action: RuleAction
    public let risk: RuleRisk
    public let status: RuleStatus

    public var id: String { ruleID + "\u{0}" + path }
    public var name: String { (path as NSString).lastPathComponent }

    /// Safe, verified rules are ticked; experimental rules are always unticked (spec 006 §6).
    public var selectedByDefault: Bool { risk == .safe && status == .verified }
}

public struct SkippedItem: Hashable, Sendable {
    public let ruleID: String
    public let path: String
    public let reason: String
}

public struct RuleScanResult: Sendable {
    public enum State: Equatable, Sendable {
        case scanned
        /// The rule needs Full Disk Access; it is shown greyed out, never half-run.
        case needsFullDiskAccess
        /// The rule runs through the admin helper (milestone 3).
        case requiresHelper
        case notForThisMacOS
        /// A rule-level guard (an app running, an app installed) blocked it.
        case blocked(String)
        /// The rule runs an operation, not a file removal.
        case operation(String)
    }

    public let rule: CleanRule
    public var state: State
    public var candidates: [Candidate] = []
    public var skipped: [SkippedItem] = []

    public var totalBytes: Int64 { candidates.reduce(0) { $0 + $1.allocatedBytes } }
}

public struct ScanReport: Sendable {
    public let results: [RuleScanResult]
    public var candidates: [Candidate] { results.flatMap(\.candidates) }
    public var skipped: [SkippedItem] { results.flatMap(\.skipped) }
    public var totalBytes: Int64 { results.reduce(0) { $0 + $1.totalBytes } }

    /// A dry run: what each item would have done, without touching anything (spec 006 §5.6).
    public var dryRunLines: [String] {
        candidates.map { "\($0.action == .delete ? "delete" : "trash") \($0.allocatedBytes) \($0.ruleID) \($0.path)" }
    }
}

/// Finds the items each rule matches (spec 006 §3.2, §5). Read-only: it never changes a file.
public struct RuleScanner: Sendable {
    public let home: Home
    public let floor: ProtectedFloor
    public let guards: GuardEnvironment
    public let hasFullDiskAccess: Bool
    public let osVersion: OperatingSystemVersion
    public let now: Date

    public init(home: Home, floor: ProtectedFloor, guards: GuardEnvironment, hasFullDiskAccess: Bool,
                osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion, now: Date = Date()) {
        self.home = home
        self.floor = floor
        self.guards = guards
        self.hasFullDiskAccess = hasFullDiskAccess
        self.osVersion = osVersion
        self.now = now
    }

    /// Scans rules with one shared sizer, so a hard link or clone found by two rules counts once.
    public func scan(_ rules: [CleanRule]) -> ScanReport {
        let sizer = Sizer()
        return ScanReport(results: rules.map { scan($0, sizer: sizer) })
    }

    public func scan(_ rule: CleanRule, sizer: Sizer = Sizer()) -> RuleScanResult {
        var result = RuleScanResult(rule: rule, state: .scanned)
        if !Self.supports(rule.macOS, osVersion) { result.state = .notForThisMacOS; return result }
        if rule.privilege == .helper { result.state = .requiresHelper; return result }
        if rule.needsFullDiskAccess && !hasFullDiskAccess { result.state = .needsFullDiskAccess; return result }
        if let blocked = ruleLevelGuard(rule) { result.state = .blocked(blocked); return result }
        if rule.action == .operation { result.state = .operation(rule.operationId ?? "?"); return result }

        var seenPaths: Set<String> = []
        for target in rule.targets {
            for root in concreteRoots(target.root, resolveLast: target.match != .self, excluding: rule.conditions?.excludeNames ?? []) {
                for path in items(of: target, under: root) where seenPaths.insert(path.item).inserted {
                    switch evaluate(path.item, root: path.root, target: target, rule: rule, sizer: sizer) {
                    case .candidate(let c): result.candidates.append(c)
                    case .skipped(let reason): result.skipped.append(SkippedItem(ruleID: rule.id, path: path.item, reason: reason))
                    case .ignored: break
                    }
                }
            }
        }
        result.candidates.sort { $0.path < $1.path }
        return result
    }

    // MARK: Guards

    func ruleLevelGuard(_ rule: CleanRule) -> String? {
        guard let g = rule.guards else { return nil }
        do {
            if let apps = g.appsNotRunning, !apps.isEmpty {
                let running = try guards.runningBundleIDs()
                if let app = apps.first(where: running.contains) { return "\(app) is running" }
            }
            if let procs = g.processesNotRunning, !procs.isEmpty {
                let running = try guards.runningProcessNames()
                if let p = procs.first(where: running.contains) { return "\(p) is running" }
            }
            if let app = g.onlyIfAppMissing, try guards.isAppInstalled(bundleID: app) {
                return "\(app) is installed"
            }
        } catch {
            return "\(error)"
        }
        return nil
    }

    static func supports(_ range: MacOSRange?, _ v: OperatingSystemVersion) -> Bool {
        guard let range else { return true }
        func parse(_ s: String) -> [Int] { s.split(separator: ".").compactMap { Int($0) } + [0, 0, 0] }
        let current = [v.majorVersion, v.minorVersion, v.patchVersion]
        let min = Array(parse(range.min).prefix(3))
        if current.lexicographicallyPrecedes(min) { return false }
        if let maxS = range.max, Array(parse(maxS).prefix(3)).lexicographicallyPrecedes(current) { return false }
        return true
    }

    // MARK: Finding items

    /// Expands a target root (which may contain `*` components) into real, existing folders.
    /// Wildcard components never pass through a symlink.
    /// `excluding` also applies to the names a wildcard component matches, so a rule can skip
    /// whole containers (for example `com.apple.*`) as well as items.
    func concreteRoots(_ rulePath: String, resolveLast: Bool = true, excluding: [String] = []) -> [String] {
        guard let expanded = home.expand(rulePath), let normalized = PathNormalizer.normalize(expanded) else { return [] }
        var prefixes = [""]
        for comp in PathNormalizer.components(normalized) {
            if comp.contains(where: { "*?[".contains($0) }) {
                prefixes = prefixes.flatMap { prefix in
                    Self.children(of: prefix.isEmpty ? "/" : prefix)
                        .filter { Glob.match(comp, $0) }
                        .filter { name in !excluding.contains { Glob.matchCaseInsensitive($0, name) } }
                        .map { prefix + "/" + $0 }
                        .filter { FileStatus.lstat($0)?.isDirectory == true }
                }
            } else {
                prefixes = prefixes.map { $0 + "/" + comp }
            }
        }
        return prefixes.compactMap { p in
            if resolveLast {
                guard let real = PathNormalizer.realPath(p), FileStatus.lstat(real)?.isDirectory == true else { return nil }
                return real
            }
            // A `self` target is itself the item: resolve only its parent, so a symlinked item
            // is seen as a symlink (and skipped) rather than followed.
            let ns = p as NSString
            guard let parent = PathNormalizer.realPath(ns.deletingLastPathComponent),
                  FileStatus.lstat(parent + "/" + ns.lastPathComponent) != nil else { return nil }
            return parent + "/" + ns.lastPathComponent
        }
    }

    struct FoundPath: Hashable { let item: String; let root: String }

    func items(of target: RuleTarget, under root: String) -> [FoundPath] {
        switch target.match {
        case .self:
            // The root itself is the item; its parent is the containment root.
            let parent = (root as NSString).deletingLastPathComponent
            return [FoundPath(item: root, root: parent)]
        case .children:
            return Self.children(of: root).map { FoundPath(item: root + "/" + $0, root: root) }
        case .glob:
            let parts = (target.pattern ?? "").split(separator: "/").map(String.init)
            var level = [root]
            for (i, part) in parts.enumerated() {
                level = level.flatMap { dir in
                    Self.children(of: dir).filter { Glob.match(part, $0) }.map { dir + "/" + $0 }
                        .filter { i == parts.count - 1 || FileStatus.lstat($0)?.isDirectory == true }
                }
            }
            return level.map { FoundPath(item: $0, root: root) }
        case .types:
            let wanted = (target.types ?? []).compactMap { UTType($0) }
            var found: [FoundPath] = []
            func walk(_ dir: String, depth: Int) {
                for name in Self.children(of: dir) {
                    let p = dir + "/" + name
                    guard let st = FileStatus.lstat(p), !st.isSymlink else { continue }
                    let ext = (name as NSString).pathExtension
                    if let type = UTType(filenameExtension: ext), wanted.contains(where: { type.conforms(to: $0) }) {
                        found.append(FoundPath(item: p, root: root))
                    } else if st.isDirectory, depth < target.depth,
                              !ProtectedFloor.packageExtensions.contains(PathNormalizer.fold(ext)) {
                        walk(p, depth: depth + 1)
                    }
                }
            }
            walk(root, depth: 1)
            return found
        }
    }

    static func children(of dir: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted()
    }

    // MARK: Checking one item

    enum Evaluation { case candidate(Candidate), skipped(String), ignored }

    func evaluate(_ path: String, root: String, target: RuleTarget, rule: CleanRule, sizer: Sizer) -> Evaluation {
        guard let st = FileStatus.lstat(path) else { return .ignored }
        if st.isSymlink { return .skipped("it is a symbolic link") }
        switch target.itemKind {
        case .file where st.isDirectory, .directory where !st.isDirectory: return .ignored
        default: break
        }
        let name = (path as NSString).lastPathComponent
        if let excludes = rule.conditions?.excludeNames, excludes.contains(where: { Glob.matchCaseInsensitive($0, name) }) {
            return .ignored
        }
        do { try Containment.validate(item: path, root: root) } catch {
            return .skipped(error.description)
        }
        if case .protected(let why) = floor.verdict(for: path, context: .rule) { return .skipped("protected: \(why)") }

        if let owner = rule.conditions?.owner {
            let wanted: UInt32 = owner == .root ? 0 : home.userID
            if st.userID != wanted { return .ignored }
        }
        if rule.conditions?.launchProgramMissing == true {
            switch Self.launchProgramExists(plist: path) {
            case .some(true): return .ignored
            case .none: return .skipped("couldn't read the launch item")
            case .some(false): break
            }
        }
        if rule.guards?.skipIfOwnerAppRunning == true, name.contains(".") {
            do {
                let running = try guards.runningBundleIDs().map(PathNormalizer.fold)
                if running.contains(PathNormalizer.fold(name)) { return .skipped("\(name) is running") }
            } catch {
                return .skipped("\(error)")
            }
        }

        let m = sizer.measure(path)
        if m.crossesVolume { return .skipped("it contains another volume") }
        if m.containsLockedItem { return .skipped("it contains a locked item") }
        if let days = rule.conditions?.minAgeDays, days > 0,
           now.timeIntervalSince(m.newestModification) < Double(days) * 86_400 { return .ignored }
        if let min = rule.conditions?.minSizeBytes, m.allocatedBytes < min { return .ignored }

        return .candidate(Candidate(ruleID: rule.id, path: path, root: root, identity: st.identity,
                                    isDirectory: st.isDirectory, allocatedBytes: m.allocatedBytes,
                                    newestModification: m.newestModification,
                                    action: rule.action, risk: rule.risk, status: rule.status))
    }

    /// For broken login items: does the plist's `Program` or `ProgramArguments[0]` exist?
    /// nil when the plist can't be read.
    static func launchProgramExists(plist path: String) -> Bool? {
        guard let data = FileManager.default.contents(atPath: path),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        let program = dict["Program"] as? String ?? (dict["ProgramArguments"] as? [String])?.first
        guard let program, program.hasPrefix("/") else { return nil }
        return FileStatus.lstat(program) != nil
    }
}
