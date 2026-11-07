import Foundation
import SafetyFloor

/// An item the admin helper reported from a zone scan, reduced to what rules need. (RuleEngine
/// doesn't depend on the helper protocol; the app converts.)
public struct HelperFoundItem: Sendable, Hashable {
    public let handle: UUID
    public let zone: HelperZone
    public let path: String
    public let allocatedBytes: Int64
    public let modified: Date
    public let isDirectory: Bool
    /// For launch items: does the program exist?
    public let launchProgramExists: Bool?

    public init(handle: UUID, zone: HelperZone, path: String, allocatedBytes: Int64, modified: Date, isDirectory: Bool, launchProgramExists: Bool?) {
        self.handle = handle; self.zone = zone; self.path = path; self.allocatedBytes = allocatedBytes
        self.modified = modified; self.isDirectory = isDirectory; self.launchProgramExists = launchProgramExists
    }
}

/// Applies a helper rule's targets and conditions to the items the helper found in its zone.
/// The helper has already applied the zone rules, deny list and floor; this only narrows.
public enum HelperRuleMatcher {
    public static func result(for rule: CleanRule, items: [HelperFoundItem], home: Home, now: Date = Date()) -> RuleScanResult {
        guard rule.privilege == .helper, let zone = rule.zone else { return RuleScanResult(rule: rule, state: .requiresHelper) }
        var out: [Candidate] = []
        for item in items where item.zone == zone {
            let parent = (item.path as NSString).deletingLastPathComponent
            let name = (item.path as NSString).lastPathComponent
            let matchesTarget = rule.targets.contains { t in
                guard let root = home.expand(t.root).flatMap(PathNormalizer.normalize),
                      PathNormalizer.fold(root) == PathNormalizer.fold(PathNormalizer.normalize(parent) ?? parent) else { return false }
                switch t.match {
                case .children: return true
                case .glob: return Glob.matchCaseInsensitive(t.pattern ?? "", name)
                case .self, .types: return false
                }
            }
            guard matchesTarget else { continue }
            if let ex = rule.conditions?.excludeNames, ex.contains(where: { Glob.matchCaseInsensitive($0, name) }) { continue }
            if rule.conditions?.launchProgramMissing == true, item.launchProgramExists != false { continue }
            if let days = rule.conditions?.minAgeDays, days > 0, now.timeIntervalSince(item.modified) < Double(days) * 86_400 { continue }
            if let min = rule.conditions?.minSizeBytes, item.allocatedBytes < min { continue }
            out.append(Candidate(ruleID: rule.id, path: item.path, root: parent, identity: ItemIdentity(device: 0, inode: 0),
                                 isDirectory: item.isDirectory, allocatedBytes: item.allocatedBytes, newestModification: item.modified,
                                 action: rule.action, risk: rule.risk, status: rule.status, helperHandle: item.handle))
        }
        return RuleScanResult(rule: rule, state: .scanned, candidates: out.sorted { $0.path < $1.path })
    }
}
