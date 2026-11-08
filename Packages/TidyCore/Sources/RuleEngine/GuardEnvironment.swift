import AppKit
import Darwin

/// What rule guards ask about the running system (spec 006 §3.1). If a question can't be
/// answered the method throws, and the scanner skips the item rather than guess.
public protocol GuardEnvironment: Sendable {
    func runningBundleIDs() throws -> Set<String>
    /// Open apps with their names, for matching items to the app that owns them (`OwnerApps`).
    func runningApps() throws -> [RunningApp]
    func runningProcessNames() throws -> Set<String>
    func isAppInstalled(bundleID: String) throws -> Bool
}

extension GuardEnvironment {
    /// Bundle IDs only, for environments that don't know app names.
    public func runningApps() throws -> [RunningApp] {
        try runningBundleIDs().sorted().map { RunningApp(bundleID: $0, name: $0) }
    }
}

public struct GuardUnavailable: Error, CustomStringConvertible {
    public let what: String
    public init(what: String) { self.what = what }
    public var description: String { "couldn't check \(what)" }
}

/// The real system: NSWorkspace for apps, libproc for process names.
public struct SystemGuardEnvironment: GuardEnvironment {
    public init() {}

    public func runningBundleIDs() throws -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    public func runningApps() throws -> [RunningApp] {
        NSWorkspace.shared.runningApplications.compactMap { r in
            guard let id = r.bundleIdentifier, !r.isTerminated else { return nil }
            return RunningApp(bundleID: id, name: r.localizedName ?? id, executableName: r.executableURL?.lastPathComponent,
                              isRegular: r.activationPolicy == .regular, pid: r.processIdentifier)
        }
    }

    public func runningProcessNames() throws -> Set<String> {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { throw GuardUnavailable(what: "running processes") }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard n > 0 else { throw GuardUnavailable(what: "running processes") }
        var names: Set<String> = []
        var buf = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        for pid in pids.prefix(Int(n)) where pid > 0 {
            if proc_name(pid, &buf, UInt32(buf.count)) > 0 {
                names.insert(buf.withUnsafeBufferPointer { String(cString: $0.baseAddress!) })
            }
        }
        return names
    }

    public func isAppInstalled(bundleID: String) throws -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }
}
