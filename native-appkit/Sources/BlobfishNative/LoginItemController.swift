import Foundation
import ServiceManagement

enum LoginItemController {
    static func sync(enabled: Bool) throws {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled { try service.register() }
        } else if service.status == .enabled {
            try service.unregister()
        }
    }
}
