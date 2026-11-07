import Foundation

/// Unloads a launch agent before its plist goes to the Trash (spec 006 §6, launch.user.broken).
public protocol LaunchItemUnloader: Sendable {
    func unload(plist path: String, userID: UInt32) throws
}

/// `launchctl bootout gui/<uid> <plist>`. A plist that isn't loaded fails harmlessly, so the
/// exit status is ignored; the plist is then trashed either way.
public struct SystemLaunchItemUnloader: LaunchItemUnloader {
    public init() {}

    public func unload(plist path: String, userID: UInt32) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(userID)", path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
    }
}
