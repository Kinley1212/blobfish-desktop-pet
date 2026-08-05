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

enum LoginItemSettingTransactionError: Error, LocalizedError {
    case rollbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .rollbackFailed(let detail):
            return "Login item setting could not be rolled back: \(detail)"
        }
    }
}

enum LoginItemSettingTransaction {
    static func apply(
        previous: Bool,
        desired: Bool,
        updateSystem: (Bool) throws -> Void,
        saveConfiguration: (Bool) throws -> Void
    ) throws {
        try updateSystem(desired)
        do {
            try saveConfiguration(desired)
        } catch {
            let saveError = error
            do {
                try updateSystem(previous)
            } catch {
                throw LoginItemSettingTransactionError.rollbackFailed(error.localizedDescription)
            }
            throw saveError
        }
    }
}
