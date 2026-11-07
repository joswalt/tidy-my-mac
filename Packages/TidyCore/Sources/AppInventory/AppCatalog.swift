import Foundation
import RuleEngine
import SafetyFloor

/// Finds installed apps (build spec §6.5, spec 013 §1): every `.app` directly in the system
/// Applications folder, one vendor-folder level below it, and in `~/Applications`. Read-only.
public struct AppCatalog: Sendable {
    public let home: Home
    /// The system Applications folder; tests pass a fixture folder.
    public let systemApplications: String
    public let signatures: AppSignatures
    public let usage: AppUsage
    /// TidyMyMac's own bundle ID: never offered.
    public let ownBundleID: String

    public init(home: Home, systemApplications: String = "/Applications", signatures: AppSignatures, usage: AppUsage,
                ownBundleID: String = "io.github.joswalt.TidyMyMac") {
        self.home = home
        self.systemApplications = systemApplications
        self.signatures = signatures
        self.usage = usage
        self.ownBundleID = ownBundleID
    }

    public struct Listing: Sendable {
        /// Apps the Applications module may offer: not Apple's, not TidyMyMac.
        public var apps: [InstalledApp]
        /// Bundle IDs of every app found, Apple's included (leftover checks treat these as installed).
        public var allBundleIDs: Set<String>
    }

    /// Lists the apps. With `measure`, each offered app is sized (allocated size).
    public func list(measure: Bool = true) -> Listing {
        var apps: [InstalledApp] = []
        var all: Set<String> = []
        let sizer = Sizer()
        for (path, location) in bundlePaths() {
            guard let st = FileStatus.lstat(path), st.isDirectory, !st.isSymlink, let info = AppBundleReader.info(path) else { continue }
            all.insert(info.bundleID)
            // Never TidyMyMac, never anything named or signed as Apple's (spec 006 §5.2).
            if info.bundleID == ownBundleID || DenyList.isAppleItem(info.bundleID) || signatures.isAppleSigned(path) { continue }
            var app = InstalledApp(path: path, location: location, name: info.name, bundleID: info.bundleID,
                                   shortVersion: info.shortVersion, buildVersion: info.buildVersion, identity: st.identity,
                                   ownerUID: st.userID, teamID: signatures.teamID(path), sparkleFeed: info.sparkleFeed,
                                   electronFeed: info.electronFeed, isFromAppStore: info.isFromAppStore)
            app.lastUsed = usage.lastUsed(path)
            if measure { app.allocatedBytes = sizer.measure(path).allocatedBytes }
            apps.append(app)
        }
        apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return Listing(apps: apps, allBundleIDs: all)
    }

    /// `.app` paths in the system folder (+ one vendor level) and `~/Applications`, real paths only.
    func bundlePaths() -> [(String, InstalledApp.Location)] {
        var out: [(String, InstalledApp.Location)] = []
        if let system = PathNormalizer.realPath(systemApplications) {
            for name in Self.children(system) {
                let p = system + "/" + name
                if name.hasSuffix(".app") { out.append((p, .system)); continue }
                guard !name.hasPrefix("."), let st = FileStatus.lstat(p), st.isDirectory, !st.isSymlink,
                      !ProtectedFloor.packageExtensions.contains(PathNormalizer.fold((name as NSString).pathExtension)) else { continue }
                for child in Self.children(p) where child.hasSuffix(".app") { out.append((p + "/" + child, .system)) }
            }
        }
        if let user = PathNormalizer.realPath(home.applications.path) {
            for name in Self.children(user) where name.hasSuffix(".app") { out.append((user + "/" + name, .user)) }
        }
        return out
    }

    static func children(_ dir: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted()
    }
}
