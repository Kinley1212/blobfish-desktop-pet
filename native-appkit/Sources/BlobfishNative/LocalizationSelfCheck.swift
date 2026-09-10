import Foundation

extension SelfCheck {
    static func localizedCatalogDisplayNames() throws -> Bool {
        let catalog = try PackCatalog(packsRoot: ResourceLocator.packsRoot())
        func isEnglish(_ value: String) -> Bool {
            !value.isEmpty && value.range(of: #"[\u3400-\u9fff]"#, options: .regularExpression) == nil
        }
        for character in try catalog.characters() {
            guard isEnglish(NativeLocalization.characterName(id: character.id, fallback: character.manifest.displayName, locale: "en")) else { return false }
            for shapes in character.manifest.diy?.shapes?.values ?? Dictionary<String, [CharacterPack.Shape]>().values {
                for shape in shapes where !isEnglish(NativeLocalization.shapeName(label: shape.label, locale: "en")) {
                    return false
                }
            }
        }
        for accessory in try catalog.accessories() {
            guard isEnglish(NativeLocalization.accessoryName(id: accessory.id, fallback: accessory.manifest.displayName, locale: "en")) else { return false }
        }
        for language in try catalog.languages() {
            guard isEnglish(NativeLocalization.languageName(id: language.id, fallback: language.manifest.displayName, locale: "en")) else { return false }
        }
        return NativeLocalization.characterName(id: "blobfish", fallback: "水滴魚", locale: "zh-CN") == "水滴鱼"
            && NativeLocalization.shapeName(label: "自定义形状", locale: "zh-CN") == "自定义形状"
            && NativeLocalization.languageName(id: "custom-pack", fallback: "Custom pack", locale: "en") == "Custom pack"
            && NativeLocalization.accessoryName(id: "alarm-clock-plum-night", fallback: "月光水母钟", locale: "en") == "Moonlight Jellyfish Clock"
            && NativeLocalization.accessoryName(id: "rilakkuma-cap-2", fallback: "轻松熊鸭舌帽2", locale: "en") == "Rilakkuma Baseball Cap (Style 2)"
            && NativeLocalization.accessoryName(id: "face-nosebleed", fallback: "犯花痴", locale: "en") == "Smitten"
    }
}
