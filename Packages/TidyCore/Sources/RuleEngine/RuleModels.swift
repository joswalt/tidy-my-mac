import Foundation
import SafetyFloor

// The rule file format (spec 006 §2–3). Every type lists its keys in `CodingKeys`, and the
// loader rejects any key not listed, so a typo can't silently drop a guard.

public enum RuleModule: String, Codable, Sendable, CaseIterable { case cleanup, applications, clutter, performance }
public enum RuleCategory: String, Codable, Sendable, CaseIterable {
    case cache, log, developer
    case aiModel = "ai-model"
    case backup, installer
    case launchItem = "launch-item"
}
public enum RuleRisk: String, Codable, Sendable, CaseIterable { case safe, caution, risky }
public enum RuleAction: String, Codable, Sendable, CaseIterable { case delete, trash, operation }
public enum RulePrivilege: String, Codable, Sendable, CaseIterable { case user, helper }
public enum RuleStatus: String, Codable, Sendable, CaseIterable { case experimental, verified }
public enum MatchMode: String, Codable, Sendable, CaseIterable { case `self`, children, glob, types }
public enum ItemKind: String, Codable, Sendable, CaseIterable { case file, directory, any }
public enum OwnerCondition: String, Codable, Sendable, CaseIterable { case currentUser, root }
public enum Licence {
    /// Licences rules may come from (spec 006 §7). GPL and Commons Clause sources are learn-only.
    public static let allowed: Set<String> = ["own", "MIT", "Apache-2.0"]
}

public struct RuleSource: Codable, Hashable, Sendable {
    public let origin: String
    public let license: String
    public let ref: String?
    public let changes: String?
    enum CodingKeys: String, CodingKey, CaseIterable { case origin, license, ref, changes }
}

public struct RuleTarget: Codable, Hashable, Sendable {
    public let root: String
    public let match: MatchMode
    public let pattern: String?
    public let types: [String]?
    public let maxDepth: Int?
    public let kind: ItemKind?
    enum CodingKeys: String, CodingKey, CaseIterable { case root, match, pattern, types, maxDepth, kind }

    public init(root: String, match: MatchMode, pattern: String? = nil, types: [String]? = nil, maxDepth: Int? = nil, kind: ItemKind? = nil) {
        self.root = root; self.match = match; self.pattern = pattern; self.types = types; self.maxDepth = maxDepth; self.kind = kind
    }

    public var depth: Int { maxDepth ?? 1 }
    public var itemKind: ItemKind { kind ?? .any }
}

public struct RuleConditions: Codable, Hashable, Sendable {
    public let minAgeDays: Int?
    public let minSizeBytes: Int64?
    public let excludeNames: [String]?
    public let owner: OwnerCondition?
    public let launchProgramMissing: Bool?
    enum CodingKeys: String, CodingKey, CaseIterable { case minAgeDays, minSizeBytes, excludeNames, owner, launchProgramMissing }
}

public struct RuleGuards: Codable, Hashable, Sendable {
    public let appsNotRunning: [String]?
    public let processesNotRunning: [String]?
    public let skipIfOwnerAppRunning: Bool?
    public let onlyIfAppMissing: String?
    enum CodingKeys: String, CodingKey, CaseIterable { case appsNotRunning, processesNotRunning, skipIfOwnerAppRunning, onlyIfAppMissing }
}

public struct MacOSRange: Codable, Hashable, Sendable {
    public let min: String
    public let max: String?
    enum CodingKeys: String, CodingKey, CaseIterable { case min, max }
}

/// A `clean` rule: items matching these targets may be removed, under these conditions, in this way.
public struct CleanRule: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let module: RuleModule
    public let category: RuleCategory
    public let risk: RuleRisk
    public let removes: String
    public let keeps: String
    public let notes: String?
    public let targets: [RuleTarget]
    public let conditions: RuleConditions?
    public let guards: RuleGuards?
    public let action: RuleAction
    public let operationId: String?
    public let privilege: RulePrivilege
    public let zone: HelperZone?
    public let needsFullDiskAccess: Bool
    public let macOS: MacOSRange?
    public let status: RuleStatus
    public let source: RuleSource
    public let evidence: [String]?
    public let reviewed: String?
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, title, module, category, risk, removes, keeps, notes, targets, conditions, guards, action,
             operationId, privilege, zone, needsFullDiskAccess, macOS, status, source, evidence, reviewed
    }
}

public enum LeftoverMatch: String, Codable, Sendable, CaseIterable { case bundleId, appName, teamId }

/// Where apps leave files, searched when an app is removed or missing (spec 006 §3.3).
public struct LeftoverLocation: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let root: String
    public let match: LeftoverMatch
    public let maxDepth: Int?
    public let privilege: RulePrivilege
    public let zone: HelperZone?
    public let needsFullDiskAccess: Bool
    public let action: RuleAction
    public let notes: String?
    public let source: RuleSource
    public let reviewed: String?
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, root, match, maxDepth, privilege, zone, needsFullDiskAccess, action, notes, source, reviewed
    }
}

public enum ProtectMatch: String, Codable, Sendable, CaseIterable { case `self`, children, glob }

/// An addition to the protected floor; it can only add, never remove (spec 006 §5).
public struct ProtectRule: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let root: String
    public let match: ProtectMatch
    public let pattern: String?
    public let reason: String
    public let source: RuleSource
    enum CodingKeys: String, CodingKey, CaseIterable { case id, root, match, pattern, reason, source }
}

/// Per-app exceptions for apps whose files don't follow the usual naming (spec 006 §3.3).
public struct AppOverride: Codable, Hashable, Sendable, Identifiable {
    public let bundleId: String
    public let extraTerms: [String]?
    public let excludeTerms: [String]?
    public let extraPaths: [String]?
    public let excludePaths: [String]?
    public let sharedWith: [String]?
    public let notes: String?
    public var id: String { bundleId }
    enum CodingKeys: String, CodingKey, CaseIterable {
        case bundleId, extraTerms, excludeTerms, extraPaths, excludePaths, sharedWith, notes
    }
}

/// An app whose own version comparator disagrees with Sparkle's, so the update check would
/// report a false update (spec 013 §4, `Rules/update-overrides.json`).
public struct UpdateOverride: Codable, Hashable, Sendable, Identifiable {
    public let bundleId: String
    public let reason: String
    public var id: String { bundleId }
    enum CodingKeys: String, CodingKey, CaseIterable { case bundleId, reason }
}

/// All rules, as loaded from the bundled `Rules/` folder.
public struct RuleSet: Sendable {
    public var cleanRules: [CleanRule] = []
    public var leftoverLocations: [LeftoverLocation] = []
    public var protectRules: [ProtectRule] = []
    public var appOverrides: [AppOverride] = []
    public var updateOverrides: [UpdateOverride] = []
    /// Which file each rule id came from, for lint messages.
    public var fileOfID: [String: String] = [:]
    /// The rule-set version is the app's build number (spec 006 §2).
    public var version: Int

    public init(version: Int) { self.version = version }

    public func cleanRule(_ id: String) -> CleanRule? { cleanRules.first { $0.id == id } }
}
