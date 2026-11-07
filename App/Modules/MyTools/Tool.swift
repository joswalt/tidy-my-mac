import RuleEngine

/// Where a My Tools tile goes: a module, and the tab or Cleanup category inside it (spec 007 §2).
/// My Tools is a launcher only; every tile opens a screen that already exists.
enum ToolDestination: Hashable {
    /// Cleanup with this rule's category selected. Opening it scans (read-only) if nothing is scanned yet.
    case cleanup(ruleID: String)
    case applications(ApplicationsModel.Tab)
    case clutter(ClutterModel.Tab)
    case spaceLens
    case performance(PerformanceView.Tab)
    case protection
    case health(HealthView.Tab)

    var module: SidebarModule {
        switch self {
        case .cleanup: .cleanup
        case .applications: .applications
        case .clutter: .myClutter
        case .spaceLens: .spaceLens
        case .performance: .performance
        case .protection: .protection
        case .health: .health
        }
    }
}

/// One single-purpose tool on the My Tools grid.
struct Tool: Identifiable, Hashable {
    let name: String
    let detail: String
    let symbol: String
    let destination: ToolDestination

    var id: String { name }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [name, detail, destination.module.title].contains { $0.localizedCaseInsensitiveContains(q) }
    }

    /// The 24 tools, in the order of the layout prototype, grouped by the module they open.
    static let all: [Tool] = [
        // Cleanup
        Tool(name: "Caches", detail: "Clear caches apps rebuild", symbol: "bubbles.and.sparkles", destination: .cleanup(ruleID: "cache.user.apps")),
        Tool(name: "Logs", detail: "Old logs and crash reports", symbol: "list.bullet.rectangle", destination: .cleanup(ruleID: "log.user")),
        Tool(name: "Xcode Junk", detail: "Build data and device support", symbol: "hammer", destination: .cleanup(ruleID: "dev.xcode.derived-data")),
        Tool(name: "Simulators", detail: "Simulators Xcode can't use", symbol: "iphone.gen3", destination: .cleanup(ruleID: "dev.simulators.unavailable")),
        Tool(name: "Local AI Models", detail: "Review big model files", symbol: "cube", destination: .cleanup(ruleID: "ai.models.ollama")),
        Tool(name: "iOS Backups", detail: "Review old phone backups", symbol: "iphone", destination: .cleanup(ruleID: "backup.ios")),
        Tool(name: "Empty Trash", detail: "Every Trash bin", symbol: "trash", destination: .cleanup(ruleID: TrashBins.ruleID)),
        Tool(name: "Broken Login Items", detail: "Launch items with no app", symbol: "bolt.slash", destination: .cleanup(ruleID: "launch.user.broken")),
        // Applications
        Tool(name: "Uninstaller", detail: "Remove apps completely", symbol: "square.grid.2x2", destination: .applications(.uninstaller)),
        Tool(name: "Unused Apps", detail: "Not opened in months", symbol: "clock", destination: .applications(.unused)),
        Tool(name: "App Leftovers", detail: "Files of deleted apps", symbol: "puzzlepiece.extension", destination: .applications(.leftovers)),
        Tool(name: "Installers", detail: "Old .dmg and .pkg files", symbol: "shippingbox", destination: .applications(.installers)),
        Tool(name: "Update Check", detail: "Newer app and macOS versions", symbol: "arrow.down.circle", destination: .applications(.updates)),
        // My Clutter and Space Lens
        Tool(name: "Large & Old Files", detail: "Big or forgotten files", symbol: "doc.badge.clock", destination: .clutter(.largeOld)),
        Tool(name: "Duplicates", detail: "Identical copies", symbol: "doc.on.doc", destination: .clutter(.duplicates)),
        Tool(name: "Downloads", detail: "Review by where they came from", symbol: "arrow.down.doc", destination: .clutter(.downloads)),
        Tool(name: "Space Lens", detail: "Map a disk or folder", symbol: "chart.pie", destination: .spaceLens),
        // Performance and Protection
        Tool(name: "Flush DNS", detail: "Reset website address lookups", symbol: "network", destination: .performance(.maintenance)),
        Tool(name: "Reindex Spotlight", detail: "Rebuild the search index", symbol: "magnifyingglass", destination: .performance(.maintenance)),
        Tool(name: "Time Machine Snapshots", detail: "Thin local snapshots", symbol: "clock.arrow.circlepath", destination: .performance(.maintenance)),
        Tool(name: "Login Items", detail: "Apps that open at login", symbol: "power", destination: .performance(.loginItems)),
        Tool(name: "Background Items", detail: "Agents and daemons", symbol: "gearshape.2", destination: .performance(.backgroundItems)),
        Tool(name: "App Permissions", detail: "Which apps can use what", symbol: "lock.shield", destination: .protection),
        // Health
        Tool(name: "Run History", detail: "What was cleaned, and Restore", symbol: "heart.text.square", destination: .health(.history)),
    ]
}
