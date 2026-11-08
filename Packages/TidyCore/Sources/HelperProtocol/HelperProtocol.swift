import Foundation
import SafetyFloor

// What the app and the root helper say to each other (spec 005 §6). Requests and replies are
// Codable values sent as Data over a single @objc method, so the Objective-C surface stays tiny.
// No request carries a file path: the app can only point at handles the helper issued.

/// Namespace and constants for the helper protocol.
public enum HelperProtocol {
    public static let moduleName = "HelperProtocol"
    /// Bumped whenever a request or reply changes shape; app and helper must match (005 §4.3).
    public static let version = 1
    public static let machServiceName = "io.github.joswalt.TidyMyMac.Helper"
    public static let launchdPlistName = "io.github.joswalt.TidyMyMac.Helper.plist"
    public static let authorizationRight = "io.github.joswalt.TidyMyMac.helper.modify"
    public static let appBundleID = "io.github.joswalt.TidyMyMac"
    public static let helperIdentifier = "io.github.joswalt.TidyMyMac.Helper"
    /// Handles expire after this long (005 §5.2).
    public static let handleLifetime: TimeInterval = 30 * 60
    /// The app treats a `hello()` slower than this as a broken helper (005 §4.3).
    public static let helloTimeout: TimeInterval = 5

    /// Code-signing requirement for a peer: Apple-issued certificate, this identifier, this team (005 §9).
    public static func requirement(identifier: String, teamID: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}

/// An opaque, random 128-bit reference to one item the helper found.
public struct HelperHandle: Codable, Hashable, Sendable {
    public let raw: UUID
    public init(_ raw: UUID = UUID()) { self.raw = raw }
}

public enum HelperRequest: Codable, Sendable, Equatable {
    // Housekeeping (no authentication)
    case hello
    case shutdown
    case cancel(jobID: UUID)
    // Read-only (no authentication)
    case scan(zone: HelperZone)
    case listLocalSnapshots
    case listPackageReceipts
    case spotlightStatus
    case listTrashed
    // Changing (admin authentication unless dry run, 005 §7)
    case remove(handles: [HelperHandle], dryRun: Bool, jobID: UUID)
    case forgetReceipt(packageID: String, dryRun: Bool)
    case flushDNS
    case reindexSpotlight(volumeUUID: String, dryRun: Bool)
    case deleteLocalSnapshot(date: String, dryRun: Bool)
    case setDaemonEnabled(handle: HelperHandle, enabled: Bool, dryRun: Bool)
    case restoreTrashed(ledgerIDs: [UUID])
    case emptyTrashed(ledgerIDs: [UUID])

    /// Changing operations need the admin right. Dry runs change nothing, and flushing the DNS
    /// cache is harmless (005 §7).
    public var needsAuthorization: Bool {
        switch self {
        case .hello, .shutdown, .cancel, .scan, .listLocalSnapshots, .listPackageReceipts, .spotlightStatus, .listTrashed, .flushDNS:
            false
        case .remove(_, let dry, _), .forgetReceipt(_, let dry), .reindexSpotlight(_, let dry),
             .deleteLocalSnapshot(_, let dry), .setDaemonEnabled(_, _, let dry):
            !dry
        case .restoreTrashed, .emptyTrashed:
            true
        }
    }
}

/// What the helper reports about a launch item it found (005 §5, launchItems zone).
public struct LaunchItemInfo: Codable, Hashable, Sendable {
    public let label: String
    public let program: String?
    public let programExists: Bool
    public init(label: String, program: String?, programExists: Bool) {
        self.label = label; self.program = program; self.programExists = programExists
    }
}

/// One item from a zone scan: a handle plus what the review screen shows.
public struct ZoneItem: Codable, Hashable, Sendable {
    public let handle: HelperHandle
    public let zone: HelperZone
    public let displayPath: String
    public let allocatedBytes: Int64
    public let modified: Date
    public let ownerUID: UInt32
    public let isDirectory: Bool
    public let launchItem: LaunchItemInfo?

    public init(handle: HelperHandle, zone: HelperZone, displayPath: String, allocatedBytes: Int64, modified: Date,
                ownerUID: UInt32, isDirectory: Bool, launchItem: LaunchItemInfo?) {
        self.handle = handle; self.zone = zone; self.displayPath = displayPath; self.allocatedBytes = allocatedBytes
        self.modified = modified; self.ownerUID = ownerUID; self.isDirectory = isDirectory; self.launchItem = launchItem
    }
}

/// The per-item outcome of a changing operation, written into the app's run log.
public struct ItemResult: Codable, Hashable, Sendable {
    public enum Outcome: String, Codable, Sendable { case done, skipped, failed }
    public let handle: HelperHandle?
    public let path: String
    public let allocatedBytes: Int64
    public let action: String
    public let outcome: Outcome
    public let reason: String?
    public let trashPath: String?
    public let ledgerID: UUID?

    public init(handle: HelperHandle?, path: String, allocatedBytes: Int64, action: String, outcome: Outcome,
                reason: String? = nil, trashPath: String? = nil, ledgerID: UUID? = nil) {
        self.handle = handle; self.path = path; self.allocatedBytes = allocatedBytes; self.action = action
        self.outcome = outcome; self.reason = reason; self.trashPath = trashPath; self.ledgerID = ledgerID
    }
}

/// One item the helper moved into a user's Trash (005 §8).
public struct LedgerEntry: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let originalPath: String
    public let trashPath: String
    public let ownerUID: UInt32
    public let ownerGID: UInt32
    public let mode: UInt16
    public let time: Date
    public let jobID: UUID
    public let callerUID: UInt32
    /// Identity of the object the helper moved (st_dev, st_ino, st_mode & S_IFMT), read before the
    /// move. Restore and empty act only when the Trash item still matches. Nil in entries written
    /// by helpers before 1.0.1; the helper refuses to restore those.
    public let device: Int32?
    public let inode: UInt64?
    public let fileType: UInt16?

    public init(id: UUID = UUID(), originalPath: String, trashPath: String, ownerUID: UInt32, ownerGID: UInt32,
                mode: UInt16, time: Date, jobID: UUID, callerUID: UInt32,
                device: Int32? = nil, inode: UInt64? = nil, fileType: UInt16? = nil) {
        self.id = id; self.originalPath = originalPath; self.trashPath = trashPath; self.ownerUID = ownerUID
        self.ownerGID = ownerGID; self.mode = mode; self.time = time; self.jobID = jobID; self.callerUID = callerUID
        self.device = device; self.inode = inode; self.fileType = fileType
    }
}

public struct VolumeStatus: Codable, Hashable, Sendable {
    public let uuid: String
    public let mountPoint: String
    public let name: String
    public let indexingEnabled: Bool?
    public init(uuid: String, mountPoint: String, name: String, indexingEnabled: Bool?) {
        self.uuid = uuid; self.mountPoint = mountPoint; self.name = name; self.indexingEnabled = indexingEnabled
    }
}

public enum HelperError: Codable, Error, Equatable, Sendable, CustomStringConvertible {
    case needsAuthorization
    case protocolMismatch(helper: Int, app: Int)
    case busy
    case notAllowed(String)
    case commandFailed(String)
    case badRequest(String)

    public var description: String {
        switch self {
        case .needsAuthorization: "An administrator password is needed for this."
        case .protocolMismatch(let h, let a): "The helper speaks protocol \(h) but the app speaks \(a); it needs repairing."
        case .busy: "The helper is busy with another job."
        case .notAllowed(let why): "Not allowed: \(why)"
        case .commandFailed(let why): "The system command failed: \(why)"
        case .badRequest(let why): "Bad request: \(why)"
        }
    }
}

public enum HelperReply: Codable, Sendable, Equatable {
    case hello(protocolVersion: Int, build: Int, uid: UInt32)
    case ok
    case items([ZoneItem])
    case results([ItemResult])
    case snapshots([String])
    case receipts([String])
    case volumes([VolumeStatus])
    case ledger([LedgerEntry])
    case failure(HelperError)
}

/// What travels over XPC: the protocol version with every request.
public struct HelperEnvelope: Codable, Sendable {
    public let protocolVersion: Int
    public let request: HelperRequest
    public init(_ request: HelperRequest, protocolVersion: Int = HelperProtocol.version) {
        self.request = request
        self.protocolVersion = protocolVersion
    }
}

/// The one XPC method. `authorization` is an `AuthorizationExternalForm` (or nil).
@objc public protocol HelperXPCProtocol {
    func perform(_ envelope: Data, authorization: Data?, reply: @escaping @Sendable (Data) -> Void)
}

public enum HelperCoding {
    public static func encode<T: Encodable>(_ value: T) -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return (try? e.encode(value)) ?? Data()
    }

    public static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(type, from: data)
    }
}
