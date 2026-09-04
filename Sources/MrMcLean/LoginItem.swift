import Foundation
import ServiceManagement

enum LoginItem {
    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        guard isSupported else { return }
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
