import Foundation
import ServiceManagement

enum LoginItem {
    private static let configuredKey = "loginItemConfigured"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Only register copies that live in an Applications folder (not dev builds).
    static var isInstalledCopy: Bool {
        Bundle.main.bundlePath.contains("/Applications/")
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Turns launch-at-login on once, the first time the installed app runs.
    /// After that the user's choice (here or in System Settings) is left alone.
    static func configureOnFirstLaunch(enabled: Bool) {
        guard isInstalledCopy, !UserDefaults.standard.bool(forKey: configuredKey) else { return }
        UserDefaults.standard.set(true, forKey: configuredKey)
        if enabled, !isEnabled {
            try? set(true)
        }
    }
}
