import Foundation

enum SpeechLanguagePolicy {
    static func compatible(_ pack: LanguagePack, characterID: String) -> Bool {
        if let ids = pack.manifest.characterPackIds { return ids.contains(characterID) }
        return pack.id.hasPrefix(characterID == "grass-buddy" ? "grass-buddy-" : "blobfish-")
    }

    static func preferredPack(character: CharacterPack, currentID: String, languages: [LanguagePack]) -> LanguagePack? {
        let compatiblePacks = languages.filter { compatible($0, characterID: character.id) }
        if let current = compatiblePacks.first(where: { $0.id == currentID }) { return current }
        let locale = languages.first(where: { $0.id == currentID })?.manifest.locale
        if let match = compatiblePacks.first(where: { $0.manifest.locale == locale }) { return match }
        // Simplified and Traditional are the same language preference, with character-specific script.
        if locale?.hasPrefix("zh") == true,
           let match = compatiblePacks.first(where: { $0.manifest.locale.hasPrefix("zh") }) { return match }
        return compatiblePacks.first(where: { $0.id == character.manifest.defaultLanguagePack }) ?? compatiblePacks.first
    }

    static func text(_ chinese: String, _ english: String, locale: String) -> String {
        if locale == "en" { return english }
        let transform = StringTransform(locale == "zh-TW" ? "Hans-Hant" : "Hant-Hans")
        let converted = chinese.applyingTransform(transform, reverse: false) ?? chinese
        return locale == "zh-TW" ? converted.replacingOccurrences(of: "沈下去", with: "沉下去") : converted
    }
}

extension AppRuntime {
    var speechLocale: String { language?.manifest.locale ?? (config.language.packId.hasSuffix("-en") ? "en" : "zh-CN") }
    var speechIsEnglish: Bool { speechLocale == "en" }
    func speechText(_ chinese: String, _ english: String) -> String {
        SpeechLanguagePolicy.text(chinese, english, locale: speechLocale)
    }
}
