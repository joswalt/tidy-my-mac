import Foundation
import SafetyFloor

// Performance › Background Items (build spec §6.9). Lists launch agents and daemons outside
// Apple's own, with their state; toggling is reversible and logged by the app. Removing broken
// ones is Cleanup's job, never this screen's.

/// Namespace marker for the SystemTasks library.
public enum SystemTasks {
    public static let moduleName = "SystemTasks"
}

public struct BackgroundItem: Identifiable, Hashable, Sendable {
    public enum Domain: String, Sendable, CaseIterable {
        /// `~/Library/LaunchAgents`: toggled by the app in the user's GUI domain.
        case userAgent
        /// `/Library/LaunchAgents`: also loaded in the user's GUI domain, toggled by the app.
        case systemAgent
        /// `/Library/LaunchDaemons`: toggled through the admin helper.
        case systemDaemon

        public var title: String {
            switch self { case .userAgent: "Your launch agents"; case .systemAgent: "Launch agents for all users"; case .systemDaemon: "Launch daemons" }
        }
        public var needsHelper: Bool { self == .systemDaemon }
    }

    public var id: String { plistPath }
    public let label: String
    public let plistPath: String
    public let domain: Domain
    public let program: String?
    public let programExists: Bool
    public var vendor: String?
    public var loaded: Bool
    public var disabled: Bool

    public init(label: String, plistPath: String, domain: Domain, program: String?, programExists: Bool,
                vendor: String? = nil, loaded: Bool = false, disabled: Bool = false) {
        self.label = label; self.plistPath = plistPath; self.domain = domain; self.program = program
        self.programExists = programExists; self.vendor = vendor; self.loaded = loaded; self.disabled = disabled
    }

    /// The launchd service target this item lives in.
    public func serviceTarget(uid: UInt32) -> String {
        domain == .systemDaemon ? "system/\(label)" : "gui/\(uid)/\(label)"
    }
}

/// Runs a command and returns its exit status and standard output. Injected so tests never call launchctl.
public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String)
}

public struct SystemCommandRunner: CommandRunner {
    public init() {}
    public func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

/// Who signed a program, for the Vendor column.
public protocol ProgramSigner: Sendable {
    func vendor(of program: String) -> String?
}

public struct BackgroundItems: Sendable {
    public let home: Home
    /// The two system folders; `HelperZone.launchItems` roots in the app, fixture folders in tests.
    public let systemAgents: URL
    public let systemDaemons: URL
    let runner: CommandRunner
    let signer: ProgramSigner?
    static let launchctl = "/bin/launchctl"

    public init(home: Home, systemAgents: URL? = nil, systemDaemons: URL? = nil, runner: CommandRunner = SystemCommandRunner(),
                signer: ProgramSigner? = nil) {
        let roots = HelperZone.launchItems.roots
        self.home = home
        self.systemAgents = systemAgents ?? URL(fileURLWithPath: roots[0], isDirectory: true)
        self.systemDaemons = systemDaemons ?? URL(fileURLWithPath: roots[1], isDirectory: true)
        self.runner = runner
        self.signer = signer
    }

    /// Every non-Apple item, grouped by domain order, then by label.
    public func list() -> [BackgroundItem] {
        let uid = home.userID
        let guiLoaded = Self.loadedLabels(runner.run(Self.launchctl, ["print", "gui/\(uid)"]).output)
        let sysLoaded = Self.loadedLabels(runner.run(Self.launchctl, ["print", "system"]).output)
        let guiDisabled = Self.disabledLabels(runner.run(Self.launchctl, ["print-disabled", "gui/\(uid)"]).output)
        let sysDisabled = Self.disabledLabels(runner.run(Self.launchctl, ["print-disabled", "system"]).output)
        var out: [BackgroundItem] = []
        for (domain, folder) in [(BackgroundItem.Domain.userAgent, home.launchAgents), (.systemAgent, systemAgents), (.systemDaemon, systemDaemons)] {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".plist") }.sorted()
            for name in names {
                let path = folder.appendingPathComponent(name).path
                guard let info = Self.parse(path), !DenyList.isAppleItem(info.label), !DenyList.isAppleItem(name) else { continue }
                let daemon = domain == .systemDaemon
                out.append(BackgroundItem(label: info.label, plistPath: path, domain: domain, program: info.program,
                                          programExists: info.program.map { FileStatus.lstat($0) != nil } ?? false,
                                          vendor: info.program.flatMap { signer?.vendor(of: $0) },
                                          loaded: (daemon ? sysLoaded : guiLoaded).contains(info.label),
                                          disabled: (daemon ? sysDisabled : guiDisabled).contains(info.label)))
            }
        }
        return out
    }

    /// Label and program from a launchd plist.
    public static func parse(_ plistPath: String) -> (label: String, program: String?)? {
        guard let data = FileManager.default.contents(atPath: plistPath),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = dict["Label"] as? String, !label.isEmpty else { return nil }
        return (label, dict["Program"] as? String ?? (dict["ProgramArguments"] as? [String])?.first)
    }

    /// Labels in the `services = { … }` block of `launchctl print <domain>`.
    public static func loadedLabels(_ output: String) -> Set<String> {
        var inServices = false
        var out: Set<String> = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !inServices {
                if t == "services = {" { inServices = true }
                continue
            }
            if t == "}" { break }
            // "<pid or 0>      <last exit or ->      <label>"
            if let label = t.split(whereSeparator: { $0 == " " || $0 == "\t" }).last { out.insert(String(label)) }
        }
        return out
    }

    /// Labels marked disabled in `launchctl print-disabled <domain>` ("label" => disabled / true).
    public static func disabledLabels(_ output: String) -> Set<String> {
        var out: Set<String> = []
        for line in output.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard value == "disabled" || value == "true" else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !label.isEmpty { out.insert(label) }
        }
        return out
    }

    public enum ToggleError: Error, CustomStringConvertible, Equatable {
        case needsHelper, appleItem, notListed, failed(String)
        public var description: String {
            switch self {
            case .needsHelper: "Launch daemons are switched through the admin helper."
            case .appleItem: "Apple's own items are never changed."
            case .notListed: "That item is no longer in its folder. Refresh the list."
            case .failed(let why): "launchctl failed: \(why)"
            }
        }
    }

    /// Switches an agent on or off in the user's GUI domain: `launchctl disable|enable`, then
    /// unload or load it so the change applies now. Reversible; the app logs it.
    public func setAgent(_ item: BackgroundItem, enabled: Bool, dryRun: Bool) -> Result<Void, ToggleError> {
        guard item.domain != .systemDaemon else { return .failure(.needsHelper) }
        guard !DenyList.isAppleItem(item.label) else { return .failure(.appleItem) }
        // Only items still listed from the agent folders (never a path from elsewhere).
        let folder = item.domain == .userAgent ? home.launchAgents : systemAgents
        guard PathNormalizer.isInside(item.plistPath, folder.path), Self.parse(item.plistPath)?.label == item.label else {
            return .failure(.notListed)
        }
        if dryRun { return .success(()) }
        let target = item.serviceTarget(uid: home.userID)
        let r = runner.run(Self.launchctl, [enabled ? "enable" : "disable", target])
        guard r.status == 0 else { return .failure(.failed("\(enabled ? "enable" : "disable") exited \(r.status)")) }
        if enabled {
            _ = runner.run(Self.launchctl, ["bootstrap", "gui/\(home.userID)", item.plistPath])
        } else {
            _ = runner.run(Self.launchctl, ["bootout", target])
        }
        return .success(())
    }
}
