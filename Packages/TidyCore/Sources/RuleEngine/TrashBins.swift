import Foundation
import SafetyFloor

/// Trash bins (build spec §6.4): ~/.Trash and each mounted volume's per-user Trash. Needs Full
/// Disk Access to list. Emptying is permanent; items TidyMyMac's helper put there (root-owned)
/// are emptied through the helper, others the user can't remove are left for Finder.
public struct TrashBin: Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let path: String
    public var items: [Candidate]
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.allocatedBytes } }
}

public enum TrashBins {
    public static let ruleID = "trash.bin"

    /// The Trash folders to look at: the home Trash, then `/Volumes/*/.Trashes/<uid>`.
    public static func folders(home: Home, volumesRoot: String = "/Volumes") -> [(title: String, path: String)] {
        var out = [("Trash", home.trash.path)]
        let vols = ((try? FileManager.default.contentsOfDirectory(atPath: volumesRoot)) ?? []).sorted()
        for v in vols {
            let p = "\(volumesRoot)/\(v)/.Trashes/\(home.userID)"
            if let st = FileStatus.lstat(p), st.isDirectory, !st.isSymlink { out.append(("Trash on \(v)", p)) }
        }
        return out
    }

    public static func scan(home: Home, floor: ProtectedFloor, volumesRoot: String = "/Volumes") -> [TrashBin] {
        let sizer = Sizer()
        return folders(home: home, volumesRoot: volumesRoot).map { f in
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: f.path)) ?? []).filter { $0 != ".DS_Store" }.sorted()
            let items: [Candidate] = names.compactMap { name in
                let p = f.path + "/" + name
                guard let st = FileStatus.lstat(p), floor.verdict(for: p, context: .manualPick) == .allowed else { return nil }
                let m = st.isSymlink ? Sizer.Measure(allocatedBytes: st.allocatedBytes) : sizer.measure(p)
                return Candidate(ruleID: ruleID, path: p, root: f.path, identity: st.identity, isDirectory: st.isDirectory,
                                 allocatedBytes: m.allocatedBytes, newestModification: m.newestModification,
                                 action: .delete, risk: .caution, status: .verified)
            }
            return TrashBin(id: f.path, title: f.title, path: f.path, items: items)
        }
    }
}

extension TrashBins {
    /// A rule-shaped description of one bin, so the review screens can show it like a category.
    public static func rule(id: String, title: String) -> CleanRule {
        CleanRule(id: id, title: title, module: .cleanup, category: .cache, risk: .caution,
                  removes: "Everything in this Trash, permanently.", keeps: "Nothing in this Trash can be restored afterwards.",
                  notes: nil, targets: [], conditions: nil, guards: nil, action: .delete, operationId: nil, privilege: .user, zone: nil,
                  needsFullDiskAccess: true, macOS: nil, status: .verified,
                  source: RuleSource(origin: "own", license: "own", ref: nil, changes: nil), evidence: ["Emptying the Trash is what Finder's Empty Trash does."],
                  reviewed: nil)
    }

    /// Scan results for the review screens: one category per bin, items re-tagged with its id.
    public static func results(home: Home, floor: ProtectedFloor, hasFullDiskAccess: Bool) -> [RuleScanResult] {
        guard hasFullDiskAccess else { return [RuleScanResult(rule: rule(id: ruleID, title: "Trash"), state: .needsFullDiskAccess)] }
        return scan(home: home, floor: floor).enumerated().map { i, bin in
            let id = i == 0 ? ruleID : "\(ruleID).\(i)"
            let items = bin.items.map {
                Candidate(ruleID: id, path: $0.path, root: $0.root, identity: $0.identity, isDirectory: $0.isDirectory,
                          allocatedBytes: $0.allocatedBytes, newestModification: $0.newestModification, action: .delete,
                          risk: .caution, status: .verified)
            }
            return RuleScanResult(rule: rule(id: id, title: bin.title), state: .scanned, candidates: items)
        }
    }

    public static func isTrashItem(_ c: Candidate) -> Bool { c.ruleID == ruleID || c.ruleID.hasPrefix(ruleID + ".") }
}
