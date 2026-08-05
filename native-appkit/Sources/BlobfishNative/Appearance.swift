import Foundation

enum AccessoryTuningLimits {
    static let ordinaryHorizontal = -30.0...30.0
    static let ordinaryVertical = -30.0...30.0
    static let clockHorizontal = -240.0...240.0
    static let clockVertical = -180.0...180.0

    static func horizontal(for accessoryID: String?) -> ClosedRange<Double> {
        isClock(accessoryID) ? clockHorizontal : ordinaryHorizontal
    }

    static func vertical(for accessoryID: String?) -> ClosedRange<Double> {
        isClock(accessoryID) ? clockVertical : ordinaryVertical
    }

    static func isClock(_ accessoryID: String?) -> Bool {
        guard let accessoryID else { return false }
        return accessoryID == "alarm-clock" || accessoryID.hasPrefix("alarm-clock-")
    }
}

struct AccessoryTuning: Equatable {
    var size = 1.0; var width = 1.0; var height = 1.0; var offsetX = 0.0; var offsetY = 0.0

    init(_ value: JSONValue?, accessoryID: String? = nil) {
        guard let object = value?.objectValue else { return }
        let horizontal = AccessoryTuningLimits.horizontal(for: accessoryID)
        let vertical = AccessoryTuningLimits.vertical(for: accessoryID)
        let isClock = AccessoryTuningLimits.isClock(accessoryID)
        size = Self.clamp(object["size"]?.numberValue, 0.4, 2, fallback: 1)
        width = isClock ? 1 : Self.clamp(object["width"]?.numberValue, 0.5, 1.8, fallback: 1)
        height = isClock ? 1 : Self.clamp(object["height"]?.numberValue, 0.5, 1.8, fallback: 1)
        offsetX = Self.clamp(object["offsetX"]?.numberValue, horizontal.lowerBound, horizontal.upperBound, fallback: 0)
        offsetY = Self.clamp(object["offsetY"]?.numberValue, vertical.lowerBound, vertical.upperBound, fallback: 0)
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
            tuning[id] = AccessoryTuning(spec, accessoryID: id)
        }
    }
}

enum AccessoryLayerOrder {
    private static let slots = ["face", "hat", "eyewear", "hand", "clock"]

    static func orderedIDs(
        equipped: [String: String],
        systemAccessoryIDs: [String] = []
    ) -> [String] {
        var result = slots.compactMap { equipped[$0] }
        for id in systemAccessoryIDs where !result.contains(id) {
            result.append(id)
        }
        return result
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
