import Foundation

final class AppRuntime {
    let configStore: NativeConfigStore
    let catalog: PackCatalog?

    private(set) var config: AppConfig
    private(set) var character: CharacterPack?
    private(set) var language: LanguagePack?
    private(set) var phraseEngine: PhraseEngine?
    private(set) var accessories: [AccessoryPack] = []
    private(set) var warnings: [String] = []

    init(applicationSupportURL: URL? = nil, packsRoot: URL? = nil) {
        let directory = applicationSupportURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BlobfishDesktopPet", isDirectory: true)
        configStore = NativeConfigStore(directoryURL: directory)
        let loaded = configStore.load()
        config = loaded.config
        if let warning = loaded.warning { warnings.append(warning) }
        do {
            catalog = try PackCatalog(packsRoot: packsRoot ?? ResourceLocator.packsRoot())
        } catch {
            catalog = nil
            warnings.append(String(describing: error))
        }
        reloadPacks()
    }

    func update(_ mutate: (inout AppConfig) -> Void) throws {
        var next = config
        mutate(&next)
        next = try next.validated()
        try configStore.save(next)
        config = next
        reloadPacks()
    }

    func phrase(event: String, context: [String: JSONValue] = [:]) -> String? {
        phraseEngine?.select(event: event, context: context)?.text
    }

    private func reloadPacks() {
        guard let catalog else { return }
        do {
            accessories = try catalog.accessories()
        } catch {
            accessories = []
            warnings.append("饰品目录加载失败：\(error)")
        }
        do {
            character = try catalog.character(id: config.pet.characterPackId)
        } catch {
            warnings.append("形象包 \(config.pet.characterPackId) 加载失败，临时使用水滴鱼：\(error)")
            character = try? catalog.character(id: AppConfig.defaults.pet.characterPackId)
        }
        do {
            let languages = try catalog.languages()
            language = character.flatMap {
                SpeechLanguagePolicy.preferredPack(character: $0, currentID: config.language.packId, languages: languages)
            }
            // Normalize old incompatible preferences in memory; the next explicit save persists it.
            if let language { config.language.packId = language.id }
        } catch {
            warnings.append("语言包 \(config.language.packId) 加载失败，暂时无法显示角色台词：\(error)")
            language = nil
        }
        phraseEngine = language.map { PhraseEngine(phrases: $0.phrases) }
    }
}
