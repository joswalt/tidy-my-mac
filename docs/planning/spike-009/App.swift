import Foundation
import ServiceManagement

// Usage: TidySpike.app/Contents/MacOS/TidySpike <register|status|call|unregister|settings>
let svc = SMAppService.daemon(plistName: "\(helperLabel).plist")

func statusText(_ s: SMAppService.Status) -> String {
    switch s {
    case .notRegistered: return "notRegistered"
    case .enabled: return "enabled"
    case .requiresApproval: return "requiresApproval"
    case .notFound: return "notFound"
    @unknown default: return "unknown(\(s.rawValue))"
    }
}

let cmd = CommandLine.arguments.dropFirst().first ?? "status"
switch cmd {
case "register":
    do { try svc.register(); print("register: ok") }
    catch { print("register error: \(error) (\((error as NSError).code))") }
    print("status: \(statusText(svc.status))")
case "unregister":
    do { try svc.unregister(); print("unregister: ok") } catch { print("unregister error: \(error)") }
case "settings":
    SMAppService.openSystemSettingsLoginItems()
case "status":
    print("status: \(statusText(svc.status))")
case "call":
    let c = NSXPCConnection(machServiceName: helperLabel, options: .privileged)
    c.remoteObjectInterface = NSXPCInterface(with: SpikeHelperProtocol.self)
    c.resume()
    let sem = DispatchSemaphore(value: 0)
    let proxy = c.remoteObjectProxyWithErrorHandler { e in print("xpc error: \(e)"); sem.signal() } as! SpikeHelperProtocol
    proxy.whoAmI { r in print("helper says: \(r)"); sem.signal() }
    _ = sem.wait(timeout: .now() + 10)
    proxy.probes { r in print("probes:\n\(r)"); sem.signal() }
    if sem.wait(timeout: .now() + 10) == .timedOut { print("xpc: timed out") }
    c.invalidate()
default:
    print("unknown command \(cmd)")
}
