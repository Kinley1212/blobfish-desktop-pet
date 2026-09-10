import Foundation

extension SelfCheck {
    static func languagePreferenceSurvivesCharacterChanges() throws -> Bool {
        let catalog = try PackCatalog()
        let languages = try catalog.languages()
        let fish = try catalog.character(id: "blobfish")
        let grass = try catalog.character(id: "grass-buddy")
        let wotou = try catalog.character(id: "blobfish-wotou")
        return SpeechLanguagePolicy.preferredPack(character: grass, currentID: "blobfish-en", languages: languages)?.id == "grass-buddy-en"
            && SpeechLanguagePolicy.preferredPack(character: fish, currentID: "grass-buddy-en", languages: languages)?.id == "blobfish-en"
            && SpeechLanguagePolicy.preferredPack(character: wotou, currentID: "blobfish-en", languages: languages)?.id == "blobfish-en"
            && SpeechLanguagePolicy.preferredPack(character: grass, currentID: "blobfish-zh-TW", languages: languages)?.id == "grass-buddy-zh-CN"
            && SpeechLanguagePolicy.preferredPack(character: fish, currentID: "grass-buddy-zh-CN", languages: languages)?.id == "blobfish-zh-TW"
            && SpeechLanguagePolicy.preferredPack(character: grass, currentID: "missing-pack", languages: languages)?.id == "grass-buddy-zh-CN"
            && SpeechLanguagePolicy.text("见到你", "Hello", locale: "zh-TW") == "見到你"
            && SpeechLanguagePolicy.text("見到你", "Hello", locale: "zh-CN") == "见到你"
    }

    @MainActor static func dialogueUpdatesWithoutCrossingLanguages() throws -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = AppRuntime(applicationSupportURL: directory)
        guard let catalog = runtime.catalog else { return false }
        try runtime.update { $0.ui.locale = "en"; $0.language.packId = "blobfish-zh-TW" }
        let chinese = try catalog.dialogue(id: "blobfish-zh-TW")
        let model = DialogueViewModel(runtime: runtime, pack: chinese) { _, _ in }
        let originalPrompt = model.prompt
        guard runtime.speechText("见到你", "Hello") == "見到你" else { return false }
        try runtime.update { $0.ui.locale = "zh-CN" }
        model.synchronize(pack: chinese)
        guard model.uiLocale == "zh-CN", model.prompt == originalPrompt else { return false }
        try runtime.update { $0.language.packId = "grass-buddy-en"; $0.pet.characterPackId = "grass-buddy" }
        let english = try catalog.dialogue(id: "grass-buddy-en")
        model.synchronize(pack: english)
        guard english.nodes.values.contains(where: { $0.prompt == model.prompt }), runtime.speechText("你好", "Hello") == "Hello" else { return false }
        // A persisted preference must survive reopening, independently of UI language.
        let reopened = AppRuntime(applicationSupportURL: directory)
        guard reopened.language?.id == "grass-buddy-en", reopened.config.ui.locale == "zh-CN" else { return false }
        var legacy = reopened.config
        legacy.language.packId = "blobfish-en"
        try reopened.configStore.save(legacy)
        let migrated = AppRuntime(applicationSupportURL: directory)
        return migrated.language?.id == "grass-buddy-en" && migrated.config.language.packId == "grass-buddy-en"
    }
}
