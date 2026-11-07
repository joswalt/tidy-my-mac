import Foundation
import HelperProtocol
import SafetyFloor

/// Runs a system command: absolute path, argument array, empty environment, timeout (005 §6.3).
public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandOutput
}

public struct CommandOutput: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public init(status: Int32, stdout: String) { self.status = status; self.stdout = stdout }
}

/// Checks an externalised authorization for the helper's admin right (005 §7).
public protocol AuthorizationChecker: Sendable {
    func isAuthorized(_ externalForm: Data?) -> Bool
}

/// Mounted local volumes, for Spotlight (005 §6.2).
public protocol VolumeSource: Sendable {
    func localVolumes() -> [(uuid: String, mountPoint: String, name: String)]
}

/// Code-signature questions about apps in /Applications (005 §5.1).
public protocol AppSignatureChecker: Sendable {
    func isAppleSigned(_ appPath: String) -> Bool
}

/// Where a calling user's home and Trash are.
public protocol UserDirectory: Sendable {
    func home(forUID uid: UInt32) -> Home?
}

/// Everything the helper needs from the outside world.
public struct HelperEnvironment: Sendable {
    /// Zone roots, normally `HelperZone.roots`; tests point them into a temp folder.
    public let zoneRoots: [HelperZone: [String]]
    public let ledgerURL: URL
    public let build: Int
    public let effectiveUID: UInt32
    public let commands: CommandRunner
    public let authorization: AuthorizationChecker
    public let volumes: VolumeSource
    public let signatures: AppSignatureChecker
    public let users: UserDirectory
    public let now: @Sendable () -> Date

    public init(zoneRoots: [HelperZone: [String]], ledgerURL: URL, build: Int, effectiveUID: UInt32,
                commands: CommandRunner, authorization: AuthorizationChecker, volumes: VolumeSource,
                signatures: AppSignatureChecker, users: UserDirectory, now: @escaping @Sendable () -> Date = { Date() }) {
        self.zoneRoots = zoneRoots; self.ledgerURL = ledgerURL; self.build = build; self.effectiveUID = effectiveUID
        self.commands = commands; self.authorization = authorization; self.volumes = volumes
        self.signatures = signatures; self.users = users; self.now = now
    }

    /// The real zones (005 §5).
    public static var systemZoneRoots: [HelperZone: [String]] {
        Dictionary(uniqueKeysWithValues: HelperZone.allCases.map { ($0, $0.roots) })
    }

    public static let systemLedgerURL = URL(fileURLWithPath: "/Library/Application Support/TidyMyMac/trash-ledger.json")
}
