/// The helper's fixed zones (spec 005 §5). Shared here so rule lint and HelperCore agree.
public enum HelperZone: String, CaseIterable, Codable, Sendable {
    case systemCaches, systemLogs, rotatedLogs, launchItems, libraryLeftovers, rootApps

    public enum Action: String, Sendable { case delete, trash }

    public var roots: [String] {
        switch self {
        case .systemCaches: ["/Library/Caches"]
        case .systemLogs: ["/Library/Logs"]
        case .rotatedLogs: ["/private/var/log"]
        case .launchItems: ["/Library/LaunchAgents", "/Library/LaunchDaemons"]
        case .libraryLeftovers: ["/Library/Application Support", "/Library/Preferences",
                                 "/Library/PrivilegedHelperTools", "/Library/Caches"]
        case .rootApps: ["/Applications"]
        }
    }

    /// Delete for caches and logs, Trash for everything else.
    public var action: Action {
        switch self {
        case .systemCaches, .systemLogs, .rotatedLogs: .delete
        case .launchItems, .libraryLeftovers, .rootApps: .trash
        }
    }
}
