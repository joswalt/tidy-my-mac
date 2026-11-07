import Foundation
import Testing
import TestSupport
import HelperCore
@testable import HelperProtocol
import SafetyFloor

/// Spec 017 §4.3 contract test: the app-side client and HelperCore talk through a real
/// NSXPCListener.anonymous() in this process.
@Suite(.serialized)
struct ContractTests {
    static let everyRequest: [HelperRequest] = [
        .hello, .cancel(jobID: UUID()), .scan(zone: .systemCaches), .listLocalSnapshots, .listPackageReceipts,
        .spotlightStatus, .listTrashed, .remove(handles: [HelperHandle()], dryRun: true, jobID: UUID()),
        .forgetReceipt(packageID: "com.example.tool", dryRun: true), .flushDNS,
        .reindexSpotlight(volumeUUID: "UUID-DATA", dryRun: true), .deleteLocalSnapshot(date: "2026-11-07-101010", dryRun: true),
        .setDaemonEnabled(handle: HelperHandle(), enabled: false, dryRun: true),
        .restoreTrashed(ledgerIDs: [UUID()]), .emptyTrashed(ledgerIDs: [UUID()]), .shutdown,
    ]

    final class Rig {
        let t: TestHome
        let world: FakeHelperWorld
        let listener: NSXPCListener
        let delegate: HelperListenerDelegate
        let client: HelperClient

        init(_ label: String) throws {
            t = try TestHome(label)
            world = FakeHelperWorld(t)
            world.commands.outputs["/usr/bin/tmutil listlocalsnapshots /"] = CommandOutput(status: 0, stdout: "com.apple.TimeMachine.2026-11-07-101010.local\n")
            world.commands.outputs["/usr/sbin/pkgutil --pkgs"] = CommandOutput(status: 0, stdout: "com.example.tool\n")
            listener = NSXPCListener.anonymous()
            delegate = HelperListenerDelegate(env: world.env, policy: .init(callerRequirement: nil, requireAdmin: false))
            listener.delegate = delegate
            listener.resume()
            client = HelperClient(connection: NSXPCConnection(listenerEndpoint: listener.endpoint))
        }

        deinit {
            client.invalidate()
            listener.invalidate()
            t.cleanUp()
        }
    }

    @Test func everyOperationRoundTrips() async throws {
        let rig = try Rig("contract")
        try rig.world.file("/Library/Caches/com.example.cache/x")
        for request in Self.everyRequest {
            let reply = try await rig.client.send(request, authorization: FakeHelperWorld.goodToken, timeout: 10)
            if case .failure(let e) = reply, e == .needsAuthorization || e == .badRequest("unreadable request") {
                Issue.record("\(request) -> \(e)")
            }
        }
        let hello = try await rig.client.send(.hello)
        #expect(hello == .hello(protocolVersion: HelperProtocol.version, build: 42, uid: getuid()))
        guard case .items(let items) = try await rig.client.send(.scan(zone: .systemCaches)) else { Issue.record("no items"); return }
        #expect(items.map { ($0.displayPath as NSString).lastPathComponent } == ["com.example.cache"])
    }

    @Test func versionMismatchAndAuthorization() async throws {
        let rig = try Rig("contract-version")
        let mismatch = try await rig.client.send(.listTrashed, protocolVersion: HelperProtocol.version + 1)
        #expect(mismatch == .failure(.protocolMismatch(helper: HelperProtocol.version, app: HelperProtocol.version + 1)))
        // hello still answers so the app can tell what to do.
        if case .hello = try await rig.client.send(.hello, protocolVersion: 999) {} else { Issue.record("hello must always answer") }
        let noAuth = try await rig.client.send(.restoreTrashed(ledgerIDs: []))
        #expect(noAuth == .failure(.needsAuthorization))
        let wrongAuth = try await rig.client.send(.emptyTrashed(ledgerIDs: []), authorization: Data("nope".utf8))
        #expect(wrongAuth == .failure(.needsAuthorization))
    }

    @Test func noRequestCarriesAPath() {
        // The app can only choose among handles and values the helper issued (005 §5.2, 017 §4.3).
        for r in Self.everyRequest {
            let json = String(decoding: HelperCoding.encode(HelperEnvelope(r)), as: UTF8.self)
            #expect(!json.contains("/") && !json.contains("\\/"), "\(r) carries a path: \(json)")
        }
    }

    @Test func shutdownIsHonoured() async throws {
        let rig = try Rig("contract-shutdown")
        #expect(!rig.delegate.shouldExit(idle: 60))
        _ = try await rig.client.send(.shutdown)
        #expect(rig.delegate.shouldExit(idle: 60))
    }

    @Test func authorizationFlags() {
        #expect(!HelperRequest.flushDNS.needsAuthorization)
        #expect(!HelperRequest.remove(handles: [], dryRun: true, jobID: UUID()).needsAuthorization)
        #expect(HelperRequest.remove(handles: [], dryRun: false, jobID: UUID()).needsAuthorization)
        #expect(HelperRequest.restoreTrashed(ledgerIDs: []).needsAuthorization)
        #expect(!HelperRequest.scan(zone: .rootApps).needsAuthorization)
    }
}
