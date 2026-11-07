import Foundation
import SafetyFloor

/// One installed `.app` bundle, as the Applications module shows it (build spec §6.5).
public struct InstalledApp: Sendable, Hashable, Identifiable {
    public enum Location: String, Sendable, Hashable {
        /// `/Applications` or a vendor folder one level below it.
        case system
        /// `~/Applications`.
        case user
    }

    /// Real path of the bundle.
    public let path: String
    public let location: Location
    public let name: String
    public let bundleID: String
    /// `CFBundleShortVersionString` (shown to people).
    public let shortVersion: String?
    /// `CFBundleVersion` (what Sparkle compares).
    public let buildVersion: String?
    public let identity: ItemIdentity
    public let ownerUID: UInt32
    public let teamID: String?
    public var allocatedBytes: Int64
    /// Spotlight's `kMDItemLastUsedDate`; nil when Spotlight has none.
    public var lastUsed: Date?
    /// Info.plist `SUFeedURL`, quotes and whitespace trimmed (spec 013 §2).
    public let sparkleFeed: String?
    /// `Contents/Resources/app-update.yml`, when it names a generic or S3 feed.
    public let electronFeed: String?
    /// `Contents/_MASReceipt/receipt` exists.
    public let isFromAppStore: Bool

    public init(path: String, location: Location, name: String, bundleID: String, shortVersion: String?, buildVersion: String?,
                identity: ItemIdentity, ownerUID: UInt32, teamID: String?, allocatedBytes: Int64 = 0, lastUsed: Date? = nil,
                sparkleFeed: String? = nil, electronFeed: String? = nil, isFromAppStore: Bool = false) {
        self.path = path; self.location = location; self.name = name; self.bundleID = bundleID
        self.shortVersion = shortVersion; self.buildVersion = buildVersion; self.identity = identity
        self.ownerUID = ownerUID; self.teamID = teamID; self.allocatedBytes = allocatedBytes; self.lastUsed = lastUsed
        self.sparkleFeed = sparkleFeed; self.electronFeed = electronFeed; self.isFromAppStore = isFromAppStore
    }

    public var id: String { path }
    public var fileName: String { (path as NSString).lastPathComponent }
    /// The folder holding the bundle (the containment root for removal).
    public var parent: String { (path as NSString).deletingLastPathComponent }
    /// "1.2 (345)", or whichever of the two exists.
    public var versionText: String {
        switch (shortVersion, buildVersion) {
        case let (s?, b?) where s != b: "\(s) (\(b))"
        case let (s?, _): s
        case let (nil, b?): b
        default: "?"
        }
    }

    /// Owned by someone else (usually root), so only the admin helper can move it (005 §5, `rootApps`).
    public func needsHelper(userID: UInt32) -> Bool { ownerUID != userID }
}

/// Reads what we need from a bundle's Info.plist and resources. Read-only.
public enum AppBundleReader {
    public struct Info: Sendable, Equatable {
        public let bundleID: String
        public let name: String
        public let shortVersion: String?
        public let buildVersion: String?
        public let sparkleFeed: String?
        public let electronFeed: String?
        public let isFromAppStore: Bool
    }

    public static func info(_ appPath: String) -> Info? {
        guard let dict = plist(appPath + "/Contents/Info.plist"),
              let id = (dict["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { return nil }
        let fileName = ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
        let display = (dict["CFBundleDisplayName"] as? String) ?? (dict["CFBundleName"] as? String)
        let name = (display?.isEmpty == false ? display! : fileName)
        return Info(bundleID: id, name: name,
                    shortVersion: nonEmpty(dict["CFBundleShortVersionString"]),
                    buildVersion: nonEmpty(dict["CFBundleVersion"]),
                    sparkleFeed: (dict["SUFeedURL"] as? String).flatMap(trimFeed),
                    electronFeed: electronFeed(appPath),
                    isFromAppStore: FileStatus.lstat(appPath + "/Contents/_MASReceipt/receipt") != nil)
    }

    static func plist(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    static func nonEmpty(_ v: Any?) -> String? {
        guard let s = (v as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return s
    }

    /// Sparkle strips surrounding quotes from the feed URL; so do we (spec 013 §2).
    public static func trimFeed(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// `<url>/latest-mac.yml` for an electron-builder app whose first provider is generic or S3.
    static func electronFeed(_ appPath: String) -> String? {
        guard let data = FileManager.default.contents(atPath: appPath + "/Contents/Resources/app-update.yml"),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return ElectronFeed.latestMacURL(appUpdateYAML: text)
    }
}
