import Observation
import ServiceManagement

/// TidyMyMac's own "Open at login" (spec 011 §1, build spec §6.9), off by default.
@MainActor @Observable
final class LoginItem {
    private(set) var isOn = SMAppService.mainApp.status == .enabled
    private(set) var needsApproval = SMAppService.mainApp.status == .requiresApproval
    var error: String?

    func refresh() {
        isOn = SMAppService.mainApp.status == .enabled
        needsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
