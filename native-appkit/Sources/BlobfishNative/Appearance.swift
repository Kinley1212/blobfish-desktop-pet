import Foundation

struct AccessoryTuning: Equatable {
    var size = 1.0; var width = 1.0; var height = 1.0; var offsetX = 0.0; var offsetY = 0.0

    init(_ value: JSONValue?) {
        guard let object = value?.objectValue else { return }
        size = Self.clamp(object["size"]?.numberValue, 0.4, 2, fallback: 1)
        width = Self.clamp(object["width"]?.numberValue, 0.5, 1.8, fallback: 1)
        height = Self.clamp(object["height"]?.numberValue, 0.5, 1.8, fallback: 1)
        offsetX = Self.clamp(object["offsetX"]?.numberValue, -30, 30, fallback: 0)
        offsetY = Self.clamp(object["offsetY"]?.numberValue, -30, 30, fallback: 0)
    }

    private static func clamp(_ value: Double?, _ minimum: Double, _ maximum: Double, fallback: Double) -> Double {
        guard let value, value.isFinite else { return fallback }
        return min(max(value, minimum), maximum)
    }
}

struct CharacterAccessories: Equatable {
    var equipped: [String: String] = [:]
    var tuning: [String: AccessoryTuning] = [:]

    init(_ value: JSONValue?) {
        guard let object = value?.objectValue else { return }
        for (slot, id) in object["equipped"]?.objectValue ?? [:] {
            if let id = id.stringValue { equipped[slot] = id }
        }
        for (id, spec) in object["tuning"]?.objectValue ?? [:] {
            tuning[id] = AccessoryTuning(spec)
        }
    }
}

enum AppearanceJSON {
    static func accessorySpec(in config: AppConfig, characterID: String) -> CharacterAccessories {
        CharacterAccessories(config.pet.accessories[characterID])
    }

    static func replacingAccessory(
        in config: inout AppConfig,
        characterID: String,
        slot: String,
        accessoryID: String?
    ) {
        var root = config.pet.accessories[characterID]?.objectValue ?? [:]
        var equipped = root["equipped"]?.objectValue ?? [:]
        equipped[slot] = accessoryID.map(JSONValue.string) ?? .null
        root["equipped"] = .object(equipped)
        if root["tuning"] == nil { root["tuning"] = .object([:]) }
        config.pet.accessories[characterID] = .object(root)
    }
}
