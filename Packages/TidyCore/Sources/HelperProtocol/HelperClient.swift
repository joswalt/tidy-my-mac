import Foundation

/// The app's side of the XPC conversation. The app reaches the helper only through this type
/// (spec 016 §3). The contract test uses it against an in-process listener.
public final class HelperClient: @unchecked Sendable {
    public enum ClientError: Error, Equatable, CustomStringConvertible {
        case timedOut
        case connection(String)
        case badReply

        public var description: String {
            switch self {
            case .timedOut: "The helper didn't answer in time."
            case .connection(let m): "Couldn't reach the helper: \(m)"
            case .badReply: "The helper sent a reply the app doesn't understand."
            }
        }
    }

    private let connection: NSXPCConnection

    /// `connection` is configured but not yet resumed.
    public init(connection: NSXPCConnection) {
        self.connection = connection
        connection.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.resume()
    }

    /// The installed helper's Mach service, checked against its code signature (005 §9).
    public static func machServiceConnection(teamID: String) -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: HelperProtocol.machServiceName, options: .privileged)
        c.setCodeSigningRequirement(HelperProtocol.requirement(identifier: HelperProtocol.helperIdentifier, teamID: teamID))
        return c
    }

    public func invalidate() { connection.invalidate() }

    public func send(_ request: HelperRequest, authorization: Data? = nil, timeout: TimeInterval = 120,
                     protocolVersion: Int = HelperProtocol.version) async throws -> HelperReply {
        let envelope = HelperCoding.encode(HelperEnvelope(request, protocolVersion: protocolVersion))
        let once = Once()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HelperReply, Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                if once.claim() { cont.resume(throwing: ClientError.connection(error.localizedDescription)) }
            }
            guard let helper = proxy as? HelperXPCProtocol else {
                if once.claim() { cont.resume(throwing: ClientError.connection("no proxy")) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.claim() { cont.resume(throwing: ClientError.timedOut) }
            }
            helper.perform(envelope, authorization: authorization) { data in
                guard once.claim() else { return }
                if let reply = try? HelperCoding.decode(HelperReply.self, data) {
                    cont.resume(returning: reply)
                } else {
                    cont.resume(throwing: ClientError.badReply)
                }
            }
        }
    }
}

/// Resumes a continuation exactly once across racing callbacks.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
}
