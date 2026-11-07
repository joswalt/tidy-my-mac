import AppInventory
import Darwin
import Foundation
import RuleEngine
import SafetyFloor

/// The one place in the app that builds real file-system values (spec 017 §2). Everything
/// else receives them from here.
enum CompositionRoot {
    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }

    /// The rule-set version is the build number (spec 006 §2).
    static var ruleSetVersion: Int { Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0 }

    static func realHome() -> Home {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        let cacheDir = confstr(_CS_DARWIN_USER_CACHE_DIR, &buf, buf.count) > 0
            ? buf.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            : FileManager.default.temporaryDirectory.path
        return Home(root: home, temporaryDirectory: FileManager.default.temporaryDirectory,
                    userCacheDirectory: URL(fileURLWithPath: cacheDir, isDirectory: true), userID: getuid())
    }

    static func rulesFolder() -> URL? { Bundle.main.resourceURL?.appendingPathComponent("Rules", isDirectory: true) }

    enum Failure: Error, CustomStringConvertible {
        case rules(String)
        var description: String { switch self { case .rules(let m): "The built-in rules couldn't be loaded: \(m)" } }
    }

    /// Full Disk Access detection arrives in milestone 3 (spec 015); until then rules that need it
    /// show as needing it and are never half-run.
    static func makeContext() throws -> CleanupContext {
        guard let folder = rulesFolder() else { throw Failure.rules("missing Rules folder") }
        let rules: RuleSet
        do { rules = try RuleLoader.load(from: folder, version: ruleSetVersion) } catch { throw Failure.rules("\(error)") }
        return CleanupContext(home: realHome(), rules: rules, guards: SystemGuardEnvironment(), hasFullDiskAccess: false,
                              trash: SystemTrash(), unloader: SystemLaunchItemUnloader(), appVersion: appVersion)
    }

    /// Real system services for the Applications module (build spec §6.5, spec 013).
    static func makeAppServices(home: Home) -> AppServices {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return AppServices(catalog: AppCatalog(home: home, signatures: SystemAppSignatures(), usage: SpotlightAppUsage()),
                           signatures: SystemAppSignatures(), receipts: SystemPackageReceipts(),
                           fetcher: URLSessionFeedFetcher(appVersion: short), cache: UpdateCache(home: home),
                           caskroom: URL(fileURLWithPath: "/opt/homebrew/Caskroom", isDirectory: true))
    }
}

/// What the Applications module needs from the outside world, built by `CompositionRoot`.
struct AppServices: Sendable {
    let catalog: AppCatalog
    let signatures: AppSignatures
    let receipts: PackageReceipts
    let fetcher: FeedFetcher
    let cache: UpdateCache
    /// Homebrew's Caskroom (Apple Silicon prefix), read for the `brew upgrade` hint.
    let caskroom: URL
}
