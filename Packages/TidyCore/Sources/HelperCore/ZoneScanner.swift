import Foundation
import HelperProtocol
import SafetyFloor

/// What the helper remembers about a handle: where it pointed and what it was (005 §5.2).
struct HandleRecord: Sendable {
    let zone: HelperZone
    let zoneRoot: String
    /// Path components below the zone root: one, or two for a vendor folder in /Applications.
    let components: [String]
    let identities: [ItemIdentity]
    let scanned: Date
    let allocatedBytes: Int64
    let launchItem: LaunchItemInfo?

    var path: String { ([zoneRoot] + components).joined(separator: "/") }
}

/// Lists a zone's items (005 §5) and checks one entry against the zone's item rule and the
/// hard deny list (§5.1). The same checks run again at action time.
struct ZoneRules: Sendable {
    let env: HelperEnvironment

    /// nil when `name` (with status `st`) is an item of `zone`; otherwise why not.
    func refusal(zone: HelperZone, name: String, path: String, st: FileStatus, callerUID: UInt32, floor: ProtectedFloor) -> String? {
        if st.isSymlink { return "it is a symbolic link" }
        if st.isLocked { return "it is locked" }
        if name.hasPrefix(".") { return "hidden system item" }
        if case .protected(let why) = floor.verdict(for: path, context: .rule) { return "protected: \(why)" }
        let apple = DenyList.isAppleItem(name)
        switch zone {
        case .systemCaches:
            return nil
        case .systemLogs:
            return name == "TidyMyMac" ? "TidyMyMac's own logs" : nil
        case .rotatedLogs:
            guard st.isRegularFile else { return "not a file" }
            return Self.isRotatedLog(name) ? nil : "not a rotated log archive"
        case .launchItems:
            guard st.isRegularFile, name.hasSuffix(".plist") else { return "not a launch item plist" }
            return apple ? "Apple's own launch item" : nil
        case .libraryLeftovers:
            if apple { return "Apple's own item" }
            if name == "TidyMyMac" { return "TidyMyMac's own files" }
            if DenyList.libraryLeftoverNames.contains(where: { PathNormalizer.fold($0) == PathNormalizer.fold(name) }) {
                return "belongs to macOS"
            }
            return nil
        case .rootApps:
            guard st.isDirectory, name.hasSuffix(".app") else { return "not an app" }
            if apple { return "Apple's own app" }
            if st.userID == callerUID { return "you can move this app to the Trash yourself" }
            if Self.bundleID(path) == HelperProtocol.appBundleID { return "TidyMyMac itself" }
            if env.signatures.isAppleSigned(path) { return "signed by Apple" }
            return nil
        }
    }

    static func isRotatedLog(_ name: String) -> Bool {
        for ext in [".gz", ".bz2", ".xz"] where name.hasSuffix(ext) { return true }
        if let last = name.split(separator: ".").last, name.contains("."), Int(last) != nil { return true }
        return false
    }

    static func bundleID(_ appPath: String) -> String? {
        let info = appPath + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: info),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    static func launchInfo(_ plistPath: String) -> LaunchItemInfo? {
        guard let data = FileManager.default.contents(atPath: plistPath),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = dict["Label"] as? String else { return nil }
        let program = dict["Program"] as? String ?? (dict["ProgramArguments"] as? [String])?.first
        return LaunchItemInfo(label: label, program: program, programExists: program.map { FileStatus.lstat($0) != nil } ?? false)
    }

    /// Candidate entries of a zone root: direct children, plus one vendor level for rootApps.
    func entries(zone: HelperZone, root: String) -> [[String]] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).sorted()
        guard zone == .rootApps else { return names.map { [$0] } }
        var out: [[String]] = []
        for n in names {
            if n.hasSuffix(".app") { out.append([n]); continue }
            guard let st = FileStatus.lstat(root + "/" + n), st.isDirectory, !st.isSymlink, !n.hasPrefix(".") else { continue }
            for child in ((try? FileManager.default.contentsOfDirectory(atPath: root + "/" + n)) ?? []).sorted() where child.hasSuffix(".app") {
                out.append([n, child])
            }
        }
        return out
    }
}
