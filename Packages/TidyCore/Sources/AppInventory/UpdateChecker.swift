import Foundation
import SafetyFloor

/// Where an app's updates come from (spec 013 §2, in this order).
public enum UpdateSource: Sendable, Equatable, Codable {
    case appStore
    case sparkle(feed: String)
    case electron(feed: String)
    case homebrew(token: String)
    case none

    public var badge: String {
        switch self {
        case .appStore: "App Store"
        case .sparkle: "Sparkle"
        case .electron: "Electron"
        case .homebrew: "Homebrew"
        case .none: "None"
        }
    }

    public static func find(for app: InstalledApp, casks: CaskCatalog?) -> UpdateSource {
        if app.isFromAppStore { return .appStore }
        if let f = app.sparkleFeed { return .sparkle(feed: f) }
        if let f = app.electronFeed { return .electron(feed: f) }
        if let e = casks?.entry(bundleID: app.bundleID, appFileName: app.fileName), e.versions != nil { return .homebrew(token: e.token) }
        return .none
    }
}

/// The result of checking one app.
public struct UpdateStatus: Sendable, Equatable, Codable, Identifiable {
    public enum State: Sendable, Equatable, Codable {
        case updateAvailable
        case upToDate
        /// App Store apps: "Updated by the App Store", no version check.
        case appStore
        /// Not checked, and why ("No update source", "Insecure feed, not checked", a network error…).
        case notChecked(String)
    }

    public let appPath: String
    public let bundleID: String
    public let name: String
    public let source: UpdateSource
    public let state: State
    public let installedVersion: String
    public let availableVersion: String?
    public let releaseNotes: String?

    public var id: String { appPath }

    public init(app: InstalledApp, source: UpdateSource, state: State, availableVersion: String? = nil, releaseNotes: String? = nil) {
        appPath = app.path; bundleID = app.bundleID; name = app.name; self.source = source; self.state = state
        installedVersion = app.shortVersion ?? app.buildVersion ?? "?"
        self.availableVersion = availableVersion; self.releaseNotes = releaseNotes
    }
}

/// Fetches a feed. The real one is HTTPS-only with an honest User-Agent and a 15 s timeout.
public protocol FeedFetcher: Sendable {
    func fetch(_ url: URL) async throws -> Data
}

public struct FetchError: Error, CustomStringConvertible, Equatable {
    public let description: String
    public init(_ d: String) { description = d }
}

public struct URLSessionFeedFetcher: FeedFetcher {
    public let userAgent: String
    public let timeout: TimeInterval

    /// `appVersion` like "1.0": the User-Agent is `TidyMyMac/1.0 (update check)` (spec 013 §6).
    public init(appVersion: String, timeout: TimeInterval = 15) {
        userAgent = "TidyMyMac/\(appVersion) (update check)"
        self.timeout = timeout
    }

    public func fetch(_ url: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else { throw FetchError("insecure feed") }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = timeout * 4
        let (data, response) = try await URLSession(configuration: config).data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError("the server answered \(http.statusCode)")
        }
        return data
    }
}

/// Checks apps for updates (spec 013). Never installs, downloads or launches anything.
public struct UpdateChecker: Sendable {
    public static let maxConcurrent = 4

    public let fetcher: FeedFetcher
    /// The OS version compared with `minimumSystemVersion`, e.g. "26.7.1".
    public let osVersion: String
    /// Bundle IDs whose custom comparators give false positives (`Rules/update-overrides.json`).
    public let ignoredBundleIDs: Set<String>

    public init(fetcher: FeedFetcher, osVersion: String, ignoredBundleIDs: Set<String> = []) {
        self.fetcher = fetcher
        self.osVersion = osVersion
        self.ignoredBundleIDs = ignoredBundleIDs
    }

    public static var currentOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Checks every app, at most four feeds at once. Results keep the apps' order.
    public func check(_ apps: [InstalledApp], casks: CaskCatalog?) async -> [UpdateStatus] {
        var results = [UpdateStatus?](repeating: nil, count: apps.count)
        await withTaskGroup(of: (Int, UpdateStatus).self) { group in
            var next = 0
            func add() {
                guard next < apps.count else { return }
                let i = next, app = apps[i]
                next += 1
                group.addTask { (i, await self.check(app, casks: casks)) }
            }
            for _ in 0..<Self.maxConcurrent { add() }
            while let (i, status) = await group.next() {
                results[i] = status
                add()
            }
        }
        return results.compactMap { $0 }
    }

    public func check(_ app: InstalledApp, casks: CaskCatalog?) async -> UpdateStatus {
        let source = UpdateSource.find(for: app, casks: casks)
        if ignoredBundleIDs.contains(app.bundleID) { return UpdateStatus(app: app, source: source, state: .notChecked("Ignored for this app")) }
        switch source {
        case .appStore:
            return UpdateStatus(app: app, source: source, state: .appStore)
        case .none:
            return UpdateStatus(app: app, source: source, state: .notChecked("No update source"))
        case .sparkle(let feed), .electron(let feed):
            guard let url = URL(string: feed), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
                return UpdateStatus(app: app, source: source, state: .notChecked("The feed address isn't valid"))
            }
            guard scheme == "https" else { return UpdateStatus(app: app, source: source, state: .notChecked("Insecure feed, not checked")) }
            let data: Data
            do { data = try await fetcher.fetch(url) } catch {
                return UpdateStatus(app: app, source: source, state: .notChecked("Couldn't reach the feed (\(Self.describe(error)))"))
            }
            if case .electron = source { return electron(app, source: source, data: data) }
            return sparkle(app, source: source, data: data)
        case .homebrew:
            guard let entry = casks?.entry(bundleID: app.bundleID, appFileName: app.fileName), let v = entry.versions else {
                return UpdateStatus(app: app, source: source, state: .notChecked("No update source"))
            }
            return homebrew(app, source: source, short: v.short, build: v.build)
        }
    }

    func sparkle(_ app: InstalledApp, source: UpdateSource, data: Data) -> UpdateStatus {
        let items: [AppcastItem]
        do { items = try Appcast.parse(data) } catch {
            return UpdateStatus(app: app, source: source, state: .notChecked("The feed couldn't be read"))
        }
        guard let installed = app.buildVersion ?? app.shortVersion else {
            return UpdateStatus(app: app, source: source, state: .notChecked("The app has no version number"))
        }
        guard let best = Appcast.bestItem(items, installedBuild: installed, osVersion: osVersion), let v = best.version else {
            return UpdateStatus(app: app, source: source, state: .upToDate)
        }
        let newer = VersionComparator.isNewer(v, than: installed)
        return UpdateStatus(app: app, source: source, state: newer ? .updateAvailable : .upToDate,
                            availableVersion: best.shortVersion ?? v, releaseNotes: best.releaseNotesLink ?? best.link)
    }

    func electron(_ app: InstalledApp, source: UpdateSource, data: Data) -> UpdateStatus {
        guard let text = String(data: data, encoding: .utf8), let v = ElectronFeed.version(latestMacYAML: text) else {
            return UpdateStatus(app: app, source: source, state: .notChecked("The feed couldn't be read"))
        }
        guard let installed = app.shortVersion ?? app.buildVersion else {
            return UpdateStatus(app: app, source: source, state: .notChecked("The app has no version number"))
        }
        let newer = VersionComparator.isNewer(v, than: installed)
        return UpdateStatus(app: app, source: source, state: newer ? .updateAvailable : .upToDate, availableVersion: v)
    }

    /// Cask `short,build`: compare build with CFBundleVersion when both exist, else short with short.
    func homebrew(_ app: InstalledApp, source: UpdateSource, short: String, build: String?) -> UpdateStatus {
        let newer: Bool
        if let build, let installedBuild = app.buildVersion {
            newer = VersionComparator.isNewer(build, than: installedBuild)
        } else if let installedShort = app.shortVersion ?? app.buildVersion {
            newer = VersionComparator.isNewer(short, than: installedShort)
        } else {
            return UpdateStatus(app: app, source: source, state: .notChecked("The app has no version number"))
        }
        return UpdateStatus(app: app, source: source, state: newer ? .updateAvailable : .upToDate, availableVersion: short)
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? FetchError { return e.description }
        if let e = error as? URLError { return e.localizedDescription }
        return "\(error)"
    }
}

/// Small JSON caches in `Application Support/TidyMyMac/Cache/` (spec 013 §2, §6).
public struct UpdateCache: Sendable {
    public let folder: URL

    public init(home: Home) { folder = home.tidySupport.appendingPathComponent("Cache", isDirectory: true) }
    public init(folder: URL) { self.folder = folder }

    public struct Stored: Codable, Sendable {
        public let checked: Date
        public let statuses: [UpdateStatus]
        public init(checked: Date, statuses: [UpdateStatus]) { self.checked = checked; self.statuses = statuses }
    }

    /// Automatic checks run at most once a day (spec 013 §6).
    public static let automaticInterval: TimeInterval = 86_400

    var updatesFile: URL { folder.appendingPathComponent("updates.json") }
    var casksFile: URL { folder.appendingPathComponent("cask.json") }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    public func loadUpdates() -> Stored? {
        (try? Data(contentsOf: updatesFile)).flatMap { try? Self.decoder.decode(Stored.self, from: $0) }
    }

    public func save(_ stored: Stored) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.encoder.encode(stored).write(to: updatesFile, options: .atomic)
    }

    public func loadCasks() -> CaskCatalog? {
        (try? Data(contentsOf: casksFile)).flatMap { try? Self.decoder.decode(CaskCatalog.self, from: $0) }
    }

    public func save(_ casks: CaskCatalog) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.encoder.encode(casks).write(to: casksFile, options: .atomic)
    }

    /// The cached catalogue if it is less than a week old; otherwise a fresh download (kept slim),
    /// falling back to the stale copy if the download fails.
    public func casks(fetcher: FeedFetcher, now: Date = Date()) async -> CaskCatalog? {
        let cached = loadCasks()
        if let cached, now.timeIntervalSince(cached.fetched) < CaskCatalog.maxAge { return cached }
        guard let url = URL(string: CaskCatalog.url), let data = try? await fetcher.fetch(url),
              let fresh = try? CaskCatalog.parse(fullCatalogue: data, fetched: now) else { return cached }
        try? save(fresh)
        return fresh
    }
}
