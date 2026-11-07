import Darwin
import Foundation
import HelperProtocol
import SafetyFloor
import Security

/// Runs commands with `Process`: absolute path, argument array, empty environment, timeout.
public struct ProcessCommandRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandOutput {
        precondition(executable.hasPrefix("/"), "commands use absolute paths")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.environment = [:]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let deadline = Date().addingTimeInterval(timeout)
        final class Box: @unchecked Sendable { var data = Data() }
        let box = Box()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { box.data = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { p.terminate(); throw SafeRemoval.Failure(message: "\(executable) timed out") }
        group.wait()
        return CommandOutput(status: p.terminationStatus, stdout: String(decoding: box.data, as: UTF8.self))
    }
}

/// Checks the admin right without user interaction (005 §7).
public struct SystemAuthorizationChecker: AuthorizationChecker {
    public init() {}

    public func isAuthorized(_ externalForm: Data?) -> Bool {
        guard let externalForm, externalForm.count == MemoryLayout<AuthorizationExternalForm>.size else { return false }
        var ext = AuthorizationExternalForm()
        withUnsafeMutableBytes(of: &ext) { _ = externalForm.copyBytes(to: $0) }
        var ref: AuthorizationRef?
        guard AuthorizationCreateFromExternalForm(&ext, &ref) == errAuthorizationSuccess, let ref else { return false }
        defer { AuthorizationFree(ref, []) }
        return HelperProtocol.authorizationRight.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { ptr in
                var rights = AuthorizationRights(count: 1, items: ptr)
                return AuthorizationCopyRights(ref, &rights, nil, [.extendRights], nil) == errAuthorizationSuccess
            }
        }
    }

    /// Registers the right on first launch: admin group, not shared, 5 minutes (005 §7). Root only.
    public static func registerRightIfNeeded() {
        if AuthorizationRightGet(HelperProtocol.authorizationRight, nil) == errAuthorizationSuccess { return }
        var ref: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &ref) == errAuthorizationSuccess, let ref else { return }
        defer { AuthorizationFree(ref, []) }
        let rule: [String: Any] = ["class": "user", "group": "admin", "shared": false, "timeout": 300,
                                   "comment": "Lets TidyMyMac's helper change system files you reviewed."]
        _ = AuthorizationRightSet(ref, HelperProtocol.authorizationRight, rule as CFDictionary,
                                  "TidyMyMac wants to clean the items you reviewed." as CFString, nil, nil)
    }
}

public struct SystemVolumeSource: VolumeSource {
    public init() {}

    public func localVolumes() -> [(uuid: String, mountPoint: String, name: String)] {
        let keys: [URLResourceKey] = [.volumeUUIDStringKey, .volumeIsLocalKey, .volumeNameKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.volumeIsLocal == true, let uuid = v.volumeUUIDString else { return nil }
            return (uuid, url.path, v.volumeName ?? url.lastPathComponent)
        }
    }
}

public struct SystemSignatureChecker: AppSignatureChecker {
    public init() {}

    public func isAppleSigned(_ appPath: String) -> Bool {
        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: appPath) as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("anchor apple" as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecStaticCodeCheckValidity(code, [], req) == errSecSuccess
    }
}

/// Homes from the user database.
public struct SystemUserDirectory: UserDirectory {
    public init() {}

    public func home(forUID uid: UInt32) -> Home? {
        guard let pw = getpwuid(uid), let dir = pw.pointee.pw_dir else { return nil }
        let home = URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        let tmp = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        return Home(root: home, temporaryDirectory: tmp, userCacheDirectory: tmp, userID: uid)
    }

    /// Is this uid in the admin group? (005 §9: the helper refuses other callers.)
    public static func isAdmin(_ uid: UInt32) -> Bool {
        guard let pw = getpwuid(uid), let name = pw.pointee.pw_name, let admin = getgrnam("admin") else { return false }
        var groups = [Int32](repeating: 0, count: 128)
        var count: Int32 = Int32(groups.count)
        _ = getgrouplist(name, Int32(bitPattern: pw.pointee.pw_gid), &groups, &count)
        return groups.prefix(Int(count)).contains(Int32(bitPattern: admin.pointee.gr_gid))
    }
}
