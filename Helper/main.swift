// TidyMyMacHelper: the root helper (spec 005). XPC listener and wiring only; all logic is in
// HelperCore. launchd starts it on demand; it exits after 60 s with no connection (005 §3).
import Foundation
import HelperCore
import HelperProtocol

SystemAuthorizationChecker.registerRightIfNeeded()

let build = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
let environment = HelperEnvironment(
    zoneRoots: HelperEnvironment.systemZoneRoots,
    ledgerURL: HelperEnvironment.systemLedgerURL,
    build: build,
    effectiveUID: geteuid(),
    commands: ProcessCommandRunner(),
    authorization: SystemAuthorizationChecker(),
    volumes: SystemVolumeSource(),
    signatures: SystemSignatureChecker(),
    users: SystemUserDirectory()
)
let delegate = HelperListenerDelegate(
    env: environment,
    policy: .init(callerRequirement: HelperProtocol.requirement(identifier: HelperProtocol.appBundleID, teamID: HelperProtocol.teamID),
                  requireAdmin: true)
)
let listener = NSXPCListener(machServiceName: HelperProtocol.machServiceName)
listener.delegate = delegate
listener.resume()

Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
    if delegate.shouldExit(idle: 60) { exit(0) }
}
RunLoop.main.run()
