import CoreServices
import Foundation
import Security

// What the Applications module asks the running system. Each is a protocol so tests can script
// it; the real implementations below are read-only (no removal, no launching apps).

/// Code-signature questions about an app bundle.
public protocol AppSignatures: Sendable {
    /// Signed by Apple (`anchor apple`). Apple's own apps are never offered (spec 013 §1, 006 §5.2).
    func isAppleSigned(_ appPath: String) -> Bool
    /// The Team ID from the signature, if any.
    func teamID(_ appPath: String) -> String?
}

/// Spotlight's last-used date (build spec §6.5).
public protocol AppUsage: Sendable {
    func lastUsed(_ appPath: String) -> Date?
}

/// Installer package receipts (`pkgutil`), read as the user. Forgetting one is the helper's job.
public protocol PackageReceipts: Sendable {
    /// Package ids that installed this path (`pkgutil --file-info`).
    func packages(owning path: String) -> [String]
    /// All package ids (`pkgutil --pkgs`).
    func allPackages() -> [String]
    /// Absolute paths of the files a package installed (`pkgutil --pkg-info` + `--files`).
    func files(of packageID: String) -> [String]
}

public struct SystemAppSignatures: AppSignatures {
    public init() {}

    /// Checks the signature's anchor without re-hashing the whole bundle: that is enough to tell
    /// who signed it, and takes milliseconds instead of seconds for large apps.
    static let fastFlags = SecCSFlags(rawValue: kSecCSDoNotValidateResources | kSecCSDoNotValidateExecutable)

    public func isAppleSigned(_ appPath: String) -> Bool {
        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: appPath) as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("anchor apple" as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecStaticCodeCheckValidity(code, Self.fastFlags, req) == errSecSuccess
    }

    public func teamID(_ appPath: String) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: appPath) as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

public struct SpotlightAppUsage: AppUsage {
    public init() {}

    public func lastUsed(_ appPath: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, appPath as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}

/// `/usr/sbin/pkgutil` through `Process` (absolute path, argument array, no shell).
public struct SystemPackageReceipts: PackageReceipts {
    public init() {}

    public func packages(owning path: String) -> [String] {
        guard let out = Self.run(["--file-info", path]) else { return [] }
        return out.split(separator: "\n").compactMap { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("pkgid:") else { return nil }
            return s.dropFirst("pkgid:".count).trimmingCharacters(in: .whitespaces)
        }
    }

    public func allPackages() -> [String] {
        (Self.run(["--pkgs"]) ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    public func files(of packageID: String) -> [String] {
        guard let info = Self.run(["--pkg-info", packageID]), let list = Self.run(["--files", packageID]) else { return [] }
        var volume = "/", location = ""
        for line in info.split(separator: "\n") {
            if line.hasPrefix("volume: ") { volume = String(line.dropFirst(8)) }
            if line.hasPrefix("location: ") { location = String(line.dropFirst(10)) }
        }
        return ReceiptPaths.absolute(volume: volume, location: location, files: list.split(separator: "\n").map(String.init))
    }

    static func run(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public enum ReceiptPaths {
    /// Joins a receipt's volume and install location with its relative file list.
    public static func absolute(volume: String, location: String, files: [String]) -> [String] {
        let base = ([volume, location].map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }.filter { !$0.isEmpty })
        return files.filter { !$0.isEmpty }.map { "/" + (base + [$0.trimmingCharacters(in: CharacterSet(charactersIn: "/"))]).joined(separator: "/") }
    }
}
