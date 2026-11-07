import AppKit
import HelperProtocol
import Observation
import RuleEngine
import SafetyFloor
import Security
import ServiceManagement

/// The app's view of the admin helper (spec 005 §4): install, approval, health check, repair,
/// and sending requests with the admin right when needed.
@MainActor @Observable
final class HelperController {
    enum State: Equatable {
        case checking
        case notInApplications
        case notInstalled
        case needsApproval
        /// The helper only answers admin users (005 §9); a standard account can't use it.
        case needsAdminAccount
        case ready
        case broken(String)

        var isReady: Bool { self == .ready }

        var summary: String {
            switch self {
            case .checking: "Checking the helper…"
            case .notInApplications: "Move TidyMyMac to Applications"
            case .notInstalled: "Helper not installed"
            case .needsApproval: "Helper waiting for approval"
            case .needsAdminAccount: "Helper needs an admin account"
            case .ready: "Helper ready"
            case .broken: "Helper needs repair"
            }
        }
    }

    var state: State = .checking
    private var client: HelperClient?
    private let service = SMAppService.daemon(plistName: HelperProtocol.launchdPlistName)
    private var authorization: AuthorizationRef?
    /// Setup polls every second; a check can take seconds, so overlapping ones are skipped.
    private var refreshing = false
    /// The silent restart of an old helper (unregister + register) is tried once per launch,
    /// not on every poll; Install and Repair allow it again.
    private var restartTried = false

    var isInApplications: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }
    var appBuild: Int { CompositionRoot.ruleSetVersion }

    // MARK: Status

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        guard isInApplications else { state = .notInApplications; return }
        guard Self.currentUserIsAdmin() else { state = .needsAdminAccount; disconnect(); return }
        switch service.status {
        case .notRegistered: state = .notInstalled; disconnect()
        case .requiresApproval: state = .needsApproval; disconnect()
        // macOS also reports .notFound for a daemon that was simply never registered; Install
        // (register) tells the two apart, and a failing register shows as broken.
        case .notFound: if case .broken = state {} else { state = .notInstalled }; disconnect()
        case .enabled: await healthCheck()
        @unknown default: state = .broken("Unknown helper status.")
        }
    }

    /// hello() with a 5 s timeout; restarts an old helper after an app update (005 §4.3).
    private func healthCheck() async {
        for attempt in 0..<3 {
            let c = connection()
            do {
                let reply = try await c.send(.hello, timeout: HelperProtocol.helloTimeout)
                guard case .hello(let version, let build, let uid) = reply else { throw HelperClient.ClientError.badReply }
                if uid != 0 { state = .broken("The helper isn't running as root."); return }
                if version == HelperProtocol.version && build == appBuild { state = .ready; return }
                // Old helper still running: ask it to exit, then (second time) re-register silently.
                _ = try? await c.send(.shutdown, timeout: 3)
                disconnect()
                if attempt == 1 && !restartTried { restartTried = true; try? await service.unregister(); try? service.register() }
                try? await Task.sleep(for: .seconds(1))
            } catch {
                disconnect()
                if attempt == 2 { state = .broken("The helper doesn't answer (\(error)).") }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        if state != .ready { state = .broken("The helper is out of date and couldn't be restarted.") }
    }

    /// Same test as the helper's caller check (005 §9): membership of the admin group.
    private static func currentUserIsAdmin() -> Bool {
        let uid = getuid()
        guard let pw = getpwuid(uid), let name = pw.pointee.pw_name, let admin = getgrnam("admin") else { return false }
        var groups = [Int32](repeating: 0, count: 128)
        var count = Int32(groups.count)
        _ = getgrouplist(name, Int32(bitPattern: pw.pointee.pw_gid), &groups, &count)
        return groups.prefix(Int(count)).contains(Int32(bitPattern: admin.pointee.gr_gid))
    }

    private func connection() -> HelperClient {
        if let client { return client }
        let c = HelperClient(connection: HelperClient.machServiceConnection(teamID: HelperProtocol.teamID))
        client = c
        return c
    }

    private func disconnect() {
        client?.invalidate()
        client = nil
    }

    // MARK: Install, repair, remove (005 §4.1, §4.4)

    func install() async {
        restartTried = false
        var registerError: Error?
        do {
            try service.register()
        } catch {
            // "Launch denied by user" just means it needs approval in Login Items.
            registerError = error
        }
        await refresh()
        if state == .notInstalled, let registerError {
            state = .broken("macOS refused to register the helper: \(registerError.localizedDescription)")
        }
        if state == .needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    func repair() async {
        disconnect()
        try? await service.unregister()
        await install()
    }

    func remove() async {
        disconnect()
        try? await service.unregister()
        await refresh()
    }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

    // MARK: Requests

    enum RequestError: Error, CustomStringConvertible {
        case notReady
        case cancelled
        case helper(HelperError)
        var description: String {
            switch self {
            case .notReady: "The admin helper isn't ready. Open setup to install it."
            case .cancelled: "Cancelled."
            case .helper(let e): e.description
            }
        }
    }

    /// Sends a request; changing requests ask for the admin password once (005 §7).
    func send(_ request: HelperRequest) async throws -> HelperReply {
        guard state.isReady else { throw RequestError.notReady }
        let auth = request.needsAuthorization ? try authorize() : nil
        let reply = try await connection().send(request, authorization: auth)
        if case .failure(let e) = reply {
            if e == .needsAuthorization { endAuthorization() }
            throw RequestError.helper(e)
        }
        return reply
    }

    /// One password prompt per run (the right lasts 5 minutes).
    func authorize() throws -> Data {
        if authorization == nil {
            var ref: AuthorizationRef?
            guard AuthorizationCreate(nil, nil, [], &ref) == errAuthorizationSuccess else { throw RequestError.cancelled }
            authorization = ref
        }
        guard let ref = authorization else { throw RequestError.cancelled }
        let status = HelperProtocol.authorizationRight.withCString { name -> OSStatus in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { ptr in
                var rights = AuthorizationRights(count: 1, items: ptr)
                return AuthorizationCopyRights(ref, &rights, nil, [.interactionAllowed, .extendRights, .preAuthorize], nil)
            }
        }
        guard status == errAuthorizationSuccess else { throw RequestError.cancelled }
        var ext = AuthorizationExternalForm()
        guard AuthorizationMakeExternalForm(ref, &ext) == errAuthorizationSuccess else { throw RequestError.cancelled }
        return withUnsafeBytes(of: &ext) { Data($0) }
    }

    func endAuthorization() {
        if let a = authorization { AuthorizationFree(a, []) }
        authorization = nil
    }

    // MARK: Convenience

    /// Scans zones and converts to what rules need.
    func found(in zones: Set<HelperZone>) async -> [HelperFoundItem] {
        var out: [HelperFoundItem] = []
        for z in zones.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard case .items(let items)? = try? await send(.scan(zone: z)) else { continue }
            out += items.map {
                HelperFoundItem(handle: $0.handle.raw, zone: $0.zone, path: $0.displayPath, allocatedBytes: $0.allocatedBytes,
                                modified: $0.modified, isDirectory: $0.isDirectory, launchProgramExists: $0.launchItem?.programExists)
            }
        }
        return out
    }

    func ledger() async -> [LedgerEntry] {
        guard case .ledger(let e)? = try? await send(.listTrashed) else { return [] }
        return e
    }
}
