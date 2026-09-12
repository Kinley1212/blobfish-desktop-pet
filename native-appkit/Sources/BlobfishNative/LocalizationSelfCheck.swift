import Foundation

extension SelfCheck {
    static func interfaceLanguageRendering() -> Bool {
        let userText = "用户的文件 / 设置 / 水滴鱼 🐟"
        return InterfaceLanguage.text("设置", "Settings", locale: "zh-CN") == "设置"
            && InterfaceLanguage.text("设置", "Settings", locale: "zh-HK") == "設定"
            && InterfaceLanguage.text("设置", "Settings", locale: "en") == "Settings"
            && InterfaceLanguage.authored("界面 鼠标 内存 文件夹", locale: "zh-HK") == "介面 滑鼠 記憶體 資料夾"
            && InterfaceLanguage.text("窗口：\(userText)", "Window: \(userText)", locale: "zh-HK") == "視窗：" + userText
            && InterfaceLanguage.text("視窗：\(userText)", "Window: \(userText)", locale: "zh-CN") == "视窗：" + userText
            && InterfaceLanguage.text("窗口：\(userText)", "Window: \(userText)", locale: "en") == "Window: " + userText
            && InterfaceLanguage.integrationDetail("检查失败：" + userText, locale: "en") == "Check failed: " + userText
            && InterfaceLanguage.integrationDetail("未找到 codex 命令行工具", locale: "zh-HK") == "未找到 codex 命令行工具"
            && InterfaceLanguage.integrationDetail("尚未安装状态插件", locale: "en") == "Status plugin not installed"
            && NativeLocalization.characterName(id: "blobfish", fallback: "水滴鱼", locale: "zh-HK") == "水滴魚"
    }

    @MainActor static func settingsInterfaceLanguageRoundTrip() throws -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = AppRuntime(applicationSupportURL: directory)
        let model = SettingsViewModel(runtime: runtime, clockService: nil, messengerService: nil, onApply: {})
        let speechPack = model.draft.language.packId
        model.draft.pet.speed = 3.5
        model.fishDisplayName = "用户的鱼 / 設定"
        model.fishInviteInput = "未保存的用户内容"
        let rawError = "用户的文件不存在"
        model.fishInviteStatus = model.uiText("检查失败：", "Check failed: ") + rawError
        for locale in ["zh-HK", "en", "zh-CN", "zh-HK"] {
            model.draft.ui.locale = locale
            model.refreshInterfaceStatusLanguage()
            guard model.fishIdentityStatus == InterfaceLanguage.text("功能不可用", "Unavailable", locale: locale),
                  model.fishInviteStatus == InterfaceLanguage.text("检查失败：\(rawError)", "Check failed: \(rawError)", locale: locale) else { return false }
            guard model.draft.language.packId == speechPack,
                  model.draft.pet.speed == 3.5,
                  model.fishDisplayName == "用户的鱼 / 設定",
                  model.fishInviteInput == "未保存的用户内容" else { return false }
            model.apply()
            guard runtime.config.ui.locale == locale,
                  runtime.configStore.load().config.ui.locale == locale,
                  runtime.config.language.packId == speechPack else { return false }
        }
        let reopened = AppRuntime(applicationSupportURL: directory)
        return reopened.config.ui.locale == "zh-HK"
            && reopened.config.language.packId == speechPack
            && InterfaceLanguage.normalize("en-US") == "zh-CN"
    }

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
