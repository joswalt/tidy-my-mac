import Foundation
import HelperCore
import HelperProtocol
import SafetyFloor

/// A helper environment whose zones live inside a TestHome's fixture folder.
public final class FakeHelperWorld: @unchecked Sendable {
    public final class Commands: CommandRunner, @unchecked Sendable {
        public var calls: [[String]] = []
        public var outputs: [String: CommandOutput] = [:]
        let lock = NSLock()
        public init() {}
        public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandOutput {
            lock.withLock {
                calls.append([executable] + arguments)
                return outputs[([executable] + arguments).joined(separator: " ")] ?? outputs[executable] ?? CommandOutput(status: 0, stdout: "")
            }
        }
    }

    public struct Auth: AuthorizationChecker {
        public let token: Data
        public func isAuthorized(_ externalForm: Data?) -> Bool { externalForm == token }
    }

    public struct Volumes: VolumeSource {
        public let list: [(uuid: String, mountPoint: String, name: String)]
        public func localVolumes() -> [(uuid: String, mountPoint: String, name: String)] { list }
    }

    public struct Signatures: AppSignatureChecker {
        public let apple: Set<String>
        public func isAppleSigned(_ appPath: String) -> Bool { apple.contains((appPath as NSString).lastPathComponent) }
    }

    public struct Users: UserDirectory {
        public let home: Home
        public func home(forUID uid: UInt32) -> Home? { uid == home.userID ? home : nil }
    }

    public final class Clock: @unchecked Sendable {
        public var now = Date()
        public init() {}
    }

    public let t: TestHome
    public let commands = Commands()
    public let clock = Clock()
    public static let goodToken = Data("authorized".utf8)
    public var appleSigned: Set<String> = ["Safari.app"]

    public init(_ t: TestHome) { self.t = t }

    /// A zone root inside the fixture, e.g. `/Library/Caches` → `<base>/sys/Library/Caches`.
    public func root(_ real: String) -> String { t.base.path + "/sys" + real }

    @discardableResult
    public func file(_ real: String, size: Int = 64, contents: Data? = nil) throws -> String {
        let p = root(real)
        try FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try (contents ?? Data(repeating: 7, count: size)).write(to: URL(fileURLWithPath: p))
        return p
    }

    public var env: HelperEnvironment {
        var roots: [HelperZone: [String]] = [:]
        for z in HelperZone.allCases {
            roots[z] = z.roots.map { root($0) }
            for r in roots[z]! { try? FileManager.default.createDirectory(atPath: r, withIntermediateDirectories: true) }
        }
        let clock = self.clock
        return HelperEnvironment(zoneRoots: roots, ledgerURL: URL(fileURLWithPath: root("/Library/Application Support/TidyMyMac/trash-ledger.json")),
                                 build: 42, effectiveUID: getuid(), commands: commands, authorization: Auth(token: Self.goodToken),
                                 volumes: Volumes(list: [("UUID-DATA", "/", "Macintosh HD")]), signatures: Signatures(apple: appleSigned),
                                 users: Users(home: t.home), now: { clock.now })
    }
}
