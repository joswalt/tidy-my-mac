import Foundation
import HelperProtocol

/// The helper's listener delegate: checks each caller, then gives it its own `HelperService`.
public final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    public struct Policy: Sendable {
        /// The app's code-signing requirement (nil only for the in-process contract test).
        public let callerRequirement: String?
        /// Refuse callers outside the admin group (005 §9).
        public let requireAdmin: Bool

        public init(callerRequirement: String?, requireAdmin: Bool) {
            self.callerRequirement = callerRequirement
            self.requireAdmin = requireAdmin
        }
    }

    let env: HelperEnvironment
    let policy: Policy
    private let lock = NSLock()
    private var open = 0
    private var lastActivity = Date()
    private var shutdownAsked = false

    public init(env: HelperEnvironment, policy: Policy) {
        self.env = env
        self.policy = policy
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let uid = UInt32(connection.effectiveUserIdentifier)
        if policy.requireAdmin && !SystemUserDirectory.isAdmin(uid) { return false }
        if let req = policy.callerRequirement { connection.setCodeSigningRequirement(req) }
        let service = HelperService(env: env, callerUID: uid)
        connection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.exportedObject = ExportedHelper(service: service, owner: self)
        lock.withLock { open += 1; lastActivity = Date() }
        connection.invalidationHandler = { [weak self] in self?.connectionEnded() }
        connection.interruptionHandler = { [weak self] in self?.touch() }
        connection.resume()
        return true
    }

    func connectionEnded() { lock.withLock { open = max(0, open - 1); lastActivity = Date() } }
    func touch() { lock.withLock { lastActivity = Date() } }
    func requestShutdown() { lock.withLock { shutdownAsked = true } }

    /// True once no connection is open and nothing happened for `idle` seconds, or after `shutdown()`
    /// with no job running (005 §3: exits after 60 s idle).
    public func shouldExit(idle: TimeInterval) -> Bool {
        lock.withLock { (open == 0 && Date().timeIntervalSince(lastActivity) > idle) || shutdownAsked }
    }
}

final class ExportedHelper: NSObject, HelperXPCProtocol, @unchecked Sendable {
    let service: HelperService
    weak var owner: HelperListenerDelegate?

    init(service: HelperService, owner: HelperListenerDelegate) {
        self.service = service
        self.owner = owner
    }

    func perform(_ envelope: Data, authorization: Data?, reply: @escaping @Sendable (Data) -> Void) {
        owner?.touch()
        let out = service.perform(envelope, authorization: authorization)
        owner?.touch()
        if service.shutdownRequested { owner?.requestShutdown() }
        reply(out)
    }
}
