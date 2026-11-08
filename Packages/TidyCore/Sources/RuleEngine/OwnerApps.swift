import Foundation
import SafetyFloor

/// An app that is open now, as rule guards see it.
public struct RunningApp: Hashable, Sendable, Identifiable {
    public let bundleID: String
    /// The name people see, such as "Google Chrome".
    public let name: String
    /// The executable's file name, such as "Google Chrome" or "CodexBar".
    public let executableName: String?
    /// True for apps with a Dock icon. Background agents and updaters are false.
    public let isRegular: Bool
    public let pid: Int32

    public init(bundleID: String, name: String, executableName: String? = nil, isRegular: Bool = true, pid: Int32 = 0) {
        self.bundleID = bundleID; self.name = name; self.executableName = executableName
        self.isRegular = isRegular; self.pid = pid
    }

    public var id: String { "\(pid):\(bundleID)" }
}

/// Which open apps own an item in a per-app folder such as ~/Library/Caches (spec 006 §3.1,
/// `skipIfOwnerAppRunning`). Three ways an item can name its app, tried in order; the first that
/// matches anything wins:
///
/// 1. Bundle ID: `com.google.Chrome`, or something under it such as `com.google.Chrome.helper`.
/// 2. App or executable name: `Firefox`, `CodexBar`.
/// 3. Vendor: `Google` belongs to `com.google.Chrome`. Only apps with a Dock icon count here, so a
///    vendor's background updater doesn't hold every one of its folders.
public enum OwnerApps {
    /// Second parts of bundle IDs that name a hosting site, not a vendor (io.github.someone.App).
    static let notVendors: Set<String> = ["apple", "github", "gitlab", "bitbucket", "sourceforge", "googlecode", "example"]

    public static func owners(of itemName: String, among apps: [RunningApp]) -> [RunningApp] {
        let name = PathNormalizer.fold(itemName)
        guard !name.isEmpty else { return [] }

        let byBundleID = apps.filter {
            let id = PathNormalizer.fold($0.bundleID)
            return name == id || name.hasPrefix(id + ".")
        }
        if !byBundleID.isEmpty { return byBundleID }

        let byName = apps.filter { PathNormalizer.fold($0.name) == name || $0.executableName.map(PathNormalizer.fold) == name }
        if !byName.isEmpty { return byName }

        guard !name.contains("."), name.count >= 3, !notVendors.contains(name) else { return [] }
        return apps.filter { $0.isRegular && vendor(of: $0.bundleID) == name }
    }

    /// `google` for `com.google.Chrome`; nil for IDs too short to have a vendor part.
    static func vendor(of bundleID: String) -> String? {
        let parts = PathNormalizer.fold(bundleID).split(separator: ".")
        return parts.count >= 3 ? String(parts[1]) : nil
    }
}
