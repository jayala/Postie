import Observation
import ServiceManagement
import os

/// Whether Postie opens when you log in, so it can tell you about new mail without being opened first.
/// macOS keeps this setting, and it can also be changed in System Settings > General > Login Items.
@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = false
    /// Turned on, but switched off in System Settings, which is the only place it can be allowed again.
    private(set) var needsApproval = false
    private(set) var error: String?

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            Log.app.error("Could not change opening at login: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
