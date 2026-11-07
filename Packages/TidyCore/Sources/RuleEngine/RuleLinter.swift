import Foundation
import SafetyFloor

/// Automated rule lint (spec 006 §6 step 1). Every check has a named code so tests can prove
/// each one fires.
public struct LintIssue: Equatable, Sendable, CustomStringConvertible {
    public enum Code: String, Sendable, CaseIterable {
        case duplicateID, licenceNotAllowed, deleteNotCacheOrLog, riskyDeletes, safeWithoutEvidence,
             emptyText, badRoot, doubleStarGlob, patternRequired, typesRequired, maxDepthOutOfRange,
             operationIdRequired, operationIdUnexpected, targetsRequired, targetOnFloor,
             helperZoneMissing, zoneWithoutHelper, helperTargetOutsideZone, helperActionMismatch,
             leftoverActionNotTrash, protectPatternRequired, badMacOSVersion
    }

    public let code: Code
    public let ruleID: String
    public let file: String
    public let message: String

    public var description: String { "\(file): \(ruleID): \(code.rawValue): \(message)" }
}

public struct RuleLinter: Sendable {
    public let home: Home
    public let floor: ProtectedFloor

    /// `home` is any plausible home (the linter only expands paths); the floor uses it too.
    public init(home: Home) {
        self.home = home
        self.floor = ProtectedFloor(home: home)
    }

    public func lint(_ set: RuleSet) -> [LintIssue] {
        var issues: [LintIssue] = []
        func add(_ code: LintIssue.Code, _ id: String, _ msg: String) {
            issues.append(LintIssue(code: code, ruleID: id, file: set.fileOfID[id] ?? "?", message: msg))
        }

        // Ids are unique across every file and kind.
        var seen: Set<String> = []
        let allIDs = set.cleanRules.map(\.id) + set.leftoverLocations.map(\.id) + set.protectRules.map(\.id)
        for id in allIDs {
            if !seen.insert(id).inserted { add(.duplicateID, id, "id is used more than once") }
        }
        var seenOverrides: Set<String> = []
        for o in set.appOverrides where !seenOverrides.insert(o.bundleId).inserted {
            add(.duplicateID, o.bundleId, "app override listed more than once")
        }

        for r in set.cleanRules { lintClean(r, add) }
        for l in set.leftoverLocations { lintLeftover(l, add) }
        for p in set.protectRules {
            if !Licence.allowed.contains(p.source.license) { add(.licenceNotAllowed, p.id, "licence '\(p.source.license)' is not own, MIT or Apache-2.0") }
            if home.expand(p.root) == nil { add(.badRoot, p.id, "root '\(p.root)' must be absolute or start with ~, $TMPDIR or $DARWIN_USER_CACHE_DIR") }
            if p.match == .glob && (p.pattern ?? "").isEmpty { add(.protectPatternRequired, p.id, "glob protect entries need a pattern") }
            if (p.pattern ?? "").contains("**") { add(.doubleStarGlob, p.id, "'**' is not allowed") }
        }
        return issues
    }

    private func lintClean(_ r: CleanRule, _ add: (LintIssue.Code, String, String) -> Void) {
        if !Licence.allowed.contains(r.source.license) { add(.licenceNotAllowed, r.id, "licence '\(r.source.license)' is not own, MIT or Apache-2.0") }
        if r.action == .delete && !(r.category == .cache || r.category == .log) {
            add(.deleteNotCacheOrLog, r.id, "only caches and logs may be deleted; use trash")
        }
        if r.risk == .risky && r.action == .delete { add(.riskyDeletes, r.id, "risky rules never delete") }
        if r.risk == .safe && (r.evidence ?? []).filter({ !$0.isEmpty }).isEmpty {
            add(.safeWithoutEvidence, r.id, "safe rules need evidence")
        }
        if r.removes.trimmingCharacters(in: .whitespaces).isEmpty || r.keeps.trimmingCharacters(in: .whitespaces).isEmpty || r.title.isEmpty {
            add(.emptyText, r.id, "title, removes and keeps must not be empty")
        }
        if let m = r.macOS, !Self.isVersion(m.min) || !(m.max.map(Self.isVersion) ?? true) {
            add(.badMacOSVersion, r.id, "macOS versions look like 14.0")
        }
        if r.action == .operation {
            if (r.operationId ?? "").isEmpty { add(.operationIdRequired, r.id, "operation rules name an operationId") }
        } else {
            if r.operationId != nil { add(.operationIdUnexpected, r.id, "operationId is only for action 'operation'") }
            if r.targets.isEmpty { add(.targetsRequired, r.id, "rules that remove files need targets") }
        }

        switch (r.privilege, r.zone) {
        case (.helper, nil): add(.helperZoneMissing, r.id, "helper rules name a zone")
        case (.user, .some): add(.zoneWithoutHelper, r.id, "only helper rules name a zone")
        case (.helper, .some(let zone)):
            if (zone.action == .delete) != (r.action == .delete) || r.action == .operation {
                add(.helperActionMismatch, r.id, "zone \(zone.rawValue) uses \(zone.action.rawValue)")
            }
        default: break
        }

        for t in r.targets {
            if t.root.contains("**") || (t.pattern ?? "").contains("**") { add(.doubleStarGlob, r.id, "'**' is not allowed") }
            if t.match == .glob && (t.pattern ?? "").isEmpty { add(.patternRequired, r.id, "glob targets need a pattern") }
            if t.match == .types && (t.types ?? []).isEmpty { add(.typesRequired, r.id, "types targets need types") }
            if let d = t.maxDepth, !(1...3).contains(d) { add(.maxDepthOutOfRange, r.id, "maxDepth must be 1 to 3") }
            guard let root = home.expand(t.root), PathNormalizer.normalize(root) != nil else {
                add(.badRoot, r.id, "root '\(t.root)' must be absolute or start with ~, $TMPDIR or $DARWIN_USER_CACHE_DIR")
                continue
            }
            let probe = t.match == .self ? root : root + "/tidy-lint-item"
            if case .protected(let why) = floor.verdict(for: probe, context: .rule) {
                add(.targetOnFloor, r.id, "target \(t.root) overlaps the protected floor (\(why))")
            }
            if r.privilege == .helper, let zone = r.zone {
                let n = PathNormalizer.normalize(root).map(PathNormalizer.fold)
                let inZone = zone.roots.contains { PathNormalizer.fold($0) == n }
                let oneLevel = t.match == .children || (t.match == .glob && !(t.pattern ?? "").contains("/"))
                if !inZone || !oneLevel || t.depth != 1 {
                    add(.helperTargetOutsideZone, r.id, "helper targets must be direct children of a \(zone.rawValue) root")
                }
            }
        }
    }

    private func lintLeftover(_ l: LeftoverLocation, _ add: (LintIssue.Code, String, String) -> Void) {
        if !Licence.allowed.contains(l.source.license) { add(.licenceNotAllowed, l.id, "licence '\(l.source.license)' is not own, MIT or Apache-2.0") }
        if l.action != .trash { add(.leftoverActionNotTrash, l.id, "leftovers always go to the Trash") }
        if let d = l.maxDepth, !(1...3).contains(d) { add(.maxDepthOutOfRange, l.id, "maxDepth must be 1 to 3") }
        switch (l.privilege, l.zone) {
        case (.helper, nil): add(.helperZoneMissing, l.id, "helper rules name a zone")
        case (.user, .some): add(.zoneWithoutHelper, l.id, "only helper rules name a zone")
        default: break
        }
        guard let root = home.expand(l.root) else {
            add(.badRoot, l.id, "root '\(l.root)' must be absolute or start with ~, $TMPDIR or $DARWIN_USER_CACHE_DIR")
            return
        }
        if case .protected(let why) = floor.verdict(for: root + "/tidy-lint-item", context: .rule) {
            add(.targetOnFloor, l.id, "root \(l.root) overlaps the protected floor (\(why))")
        }
        if l.privilege == .helper, let zone = l.zone {
            let n = PathNormalizer.normalize(root).map(PathNormalizer.fold)
            if !zone.roots.contains(where: { PathNormalizer.fold($0) == n }) {
                add(.helperTargetOutsideZone, l.id, "helper roots must be a \(zone.rawValue) root")
            }
        }
    }

    static func isVersion(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        return (1...3).contains(parts.count) && parts.allSatisfy { Int($0) != nil }
    }
}
