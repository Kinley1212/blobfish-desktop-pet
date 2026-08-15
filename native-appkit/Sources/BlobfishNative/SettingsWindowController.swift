import AppKit
import Combine
import SwiftUI

enum QuickSettingsDraftMerge {
    static func merge(runtime: AppConfig, into draft: AppConfig) -> AppConfig {
        var next = draft
        next.pet.roamWhenNoTasks = runtime.pet.roamWhenNoTasks
        next.pet.roamWhenTasks = runtime.pet.roamWhenTasks
        next.pet.flipOnBounce = runtime.pet.flipOnBounce
        next.performance.panelEnabled = runtime.performance.panelEnabled
        next.startup.launchAtLogin = runtime.startup.launchAtLogin
        return next
    }
}

enum FishInviteCodePresentationPolicy {
    private static let prefixLength = 10
    private static let suffixLength = 6

    static func displayedCode(_ code: String, revealed: Bool) -> String? {
        guard !code.isEmpty else { return nil }
        if revealed { return code }
        guard code.count > prefixLength + suffixLength else {
            return String(repeating: "•", count: min(8, max(1, code.count)))
        }
        return "\(code.prefix(prefixLength))…\(code.suffix(suffixLength))"
    }

    static func shouldResetReveal(previousCode: String, nextCode: String, windowReopened: Bool) -> Bool {
        windowReopened || previousCode != nextCode
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var draft: AppConfig
    @Published var message = ""
    @Published var selectedSection = SettingsSection.character
    @Published var clockState: ClockState
    @Published var clockSoundDraft: ClockSoundPreferencesDraft
    @Published var timerMinutes = 25
    @Published var timerLabel = ""
    @Published var alarmLabel = ""
    @Published var alarmTime = "09:00"
    @Published var alarmMode = "daily"
    @Published var alarmDate = Date().addingTimeInterval(24 * 60 * 60)
    @Published var integrationStatuses: [String: IntegrationStatus] = [:]
    @Published var integrationBusy = Set<String>()
    @Published var updateStatus = ""
    @Published var updateProgress: Double?
    @Published var updateAvailable = false
    @Published var fishDisplayName = ""
    @Published var fishPreferences = FishFriendPreferences.defaults
    @Published var fishContacts: [FishContact] = []
    @Published var fishRelayURL = ""
    @Published var fishSetupToken = ""
    @Published var fishInviteInput = ""
    @Published var fishInviteCode = ""
    @Published private(set) var fishInviteCodeRevealed = false
    @Published var fishIdentityStatus = ""
    @Published var fishInviteStatus = ""
    @Published var fishSetupBusy = false
    @Published var fishStatusPreview = FishUserStatus.fishing

    let runtime: AppRuntime
    let characters: [CharacterPack]
    let languages: [LanguagePack]
    let accessories: [AccessoryPack]
    let clockService: ClockService?
    let integrationManager: IntegrationManager
    let updater = NativeUpdater()
    let messengerService: FishMessengerService?
    private let soundPlayer = SoundPlayer()
    private var availableUpdate: (NativeUpdateManifest, NativeUpdateManifest.Asset)?
    private let onApply: @MainActor () -> Void

    init(
        runtime: AppRuntime, clockService: ClockService?, messengerService: FishMessengerService?,
        onApply: @escaping @MainActor () -> Void
    ) {
        self.runtime = runtime
        self.clockService = clockService
        self.messengerService = messengerService
        integrationManager = IntegrationManager(supportDirectory: runtime.configStore.fileURL.deletingLastPathComponent())
        let initialClockState = clockService?.state ?? .empty
        clockState = initialClockState
        clockSoundDraft = ClockSoundPreferencesDraft(initialClockState.preferences)
        draft = runtime.config
        characters = (try? runtime.catalog?.characters()) ?? []
        languages = (try? runtime.catalog?.languages()) ?? []
        accessories = runtime.accessories
        self.onApply = onApply
        if !runtime.warnings.isEmpty { message = runtime.warnings.joined(separator: "\n") }
        refreshIntegrations()
        loadFishDrafts()
        refreshFishState()
        messengerService?.addStateObserver { [weak self] in self?.refreshFishState() }
    }

    func loadFishDrafts() {
        fishDisplayName = messengerService?.profile?.displayName ?? ""
        fishPreferences = messengerService?.preferences ?? .defaults
        fishRelayURL = messengerService?.profile?.relayURL.absoluteString ?? fishRelayURL
    }

    func refreshFishState() {
        fishContacts = messengerService?.profile?.contacts ?? []
        guard let messengerService else {
            replaceFishInviteCode("")
            fishIdentityStatus = isEnglish ? "Unavailable" : "功能不可用"
            return
        }
        guard messengerService.profileState == .available, messengerService.profile != nil else {
            replaceFishInviteCode("")
            switch messengerService.profileState {
            case .notConfigured:
                fishIdentityStatus = isEnglish ? "Not configured" : "尚未建立身份"
            case .authorizationRequired:
                fishIdentityStatus = isEnglish ? "Authorization required" : "需要明确授权读取现有身份"
            case .locked:
                fishIdentityStatus = isEnglish ? "Keychain is locked" : "系统钥匙串尚未解锁"
            case .corrupt:
                fishIdentityStatus = isEnglish ? "Stored identity is invalid" : "已保存的身份资料无效"
            case .unavailable:
                fishIdentityStatus = isEnglish ? "Keychain is unavailable" : "系统钥匙串暂时不可用"
            case .available:
                fishIdentityStatus = isEnglish ? "Identity is unavailable" : "身份暂时不可用"
            }
            return
        }
        do {
            replaceFishInviteCode(try messengerService.inviteCode())
            fishIdentityStatus = isEnglish
                ? "Valid · private key protected by Keychain"
                : "有效 · 私钥由系统钥匙串保护"
        } catch {
            replaceFishInviteCode("")
            fishIdentityStatus = isEnglish ? "Identity is invalid" : "身份资料无效"
        }
    }

    var displayedFishInviteCode: String? {
        FishInviteCodePresentationPolicy.displayedCode(
            fishInviteCode,
            revealed: fishInviteCodeRevealed
        )
    }

    func toggleFishInviteCodeReveal() {
        guard !fishInviteCode.isEmpty else { return }
        fishInviteCodeRevealed.toggle()
    }

    private func replaceFishInviteCode(_ nextCode: String) {
        if FishInviteCodePresentationPolicy.shouldResetReveal(
            previousCode: fishInviteCode,
            nextCode: nextCode,
            windowReopened: false
        ) {
            fishInviteCodeRevealed = false
        }
        fishInviteCode = nextCode
    }

    private func hideFishInviteCodeForWindowReopen() {
        if FishInviteCodePresentationPolicy.shouldResetReveal(
            previousCode: fishInviteCode,
            nextCode: fishInviteCode,
            windowReopened: true
        ) {
            fishInviteCodeRevealed = false
        }
    }

    func saveFishSettings() {
        guard let messengerService else { return }
        do {
            if messengerService.profile != nil {
                try messengerService.updateDisplayName(fishDisplayName)
            }
            try messengerService.updatePreferences(fishPreferences)
            message = isEnglish ? "Fish friend settings saved." : "鱼友设置已保存。"
        } catch { message = error.localizedDescription }
    }

    func statusFaceBinding(_ status: FishUserStatus) -> Binding<String> {
        Binding(
            get: {
                CharacterExpressionCompatibility.resolveFaceID(
                    self.fishPreferences.faceID(for: status),
                    for: self.selectedCharacter,
                    accessories: self.accessories
                ) ?? ""
            },
            set: { value in
                var values = self.fishPreferences.statusFaceIDs ?? [:]
                values[status.rawValue] = CharacterExpressionCompatibility.portableFaceID(
                    value,
                    for: self.selectedCharacter,
                    accessories: self.accessories
                ) ?? ""
                self.fishPreferences.statusFaceIDs = values
            }
        )
    }

    func quickInteractionBinding(at index: Int) -> Binding<FishRemoteInteraction> {
        Binding(
            get: {
                let actions = self.fishPreferences.effectiveQuickInteractions
                return actions.indices.contains(index) ? actions[index] : .pet
            },
            set: { selected in
                var actions = self.fishPreferences.effectiveQuickInteractions
                guard actions.indices.contains(index) else { return }
                if let otherIndex = actions.firstIndex(of: selected), otherIndex != index {
                    actions.swapAt(index, otherIndex)
                } else {
                    actions[index] = selected
                }
                self.fishPreferences.quickInteractionIDs = actions.map(\.rawValue)
            }
        )
    }

    func interactionSoundEnabledBinding(_ interaction: FishRemoteInteraction) -> Binding<Bool> {
        Binding(
            get: { self.fishPreferences.soundEnabled(for: interaction) },
            set: { enabled in
                var values = self.fishPreferences.interactionSoundEnabled ?? [:]
                values[interaction.rawValue] = enabled
                self.fishPreferences.interactionSoundEnabled = values
            }
        )
    }

    func interactionSoundBinding(_ interaction: FishRemoteInteraction) -> Binding<String> {
        Binding(
            get: { self.fishPreferences.soundID(for: interaction) },
            set: { soundID in
                var values = self.fishPreferences.interactionSoundIDs ?? [:]
                values[interaction.rawValue] = FishInteractionSoundStyle.normalized(
                    soundID,
                    for: interaction
                )
                self.fishPreferences.interactionSoundIDs = values
            }
        )
    }

    func statusAccessoryBinding(_ status: FishUserStatus) -> Binding<String> {
        Binding(
            get: { self.fishPreferences.accessoryID(for: status) ?? "" },
            set: { value in
                var values = self.fishPreferences.statusAccessoryIDs ?? [:]
                values[status.rawValue] = value
                self.fishPreferences.statusAccessoryIDs = values
            }
        )
    }

    func statusPreviewAccessorySpec(_ status: FishUserStatus) -> CharacterAccessories {
        if let stored = fishPreferences.statusAccessorySpecs?[status.rawValue] {
            return CharacterAccessories(stored)
        }
        var specification = AppearanceJSON.accessorySpec(
            in: draft,
            characterID: draft.pet.characterPackId
        )
        if let id = fishPreferences.accessoryID(for: status),
           let slot = accessories.first(where: { $0.id == id })?.manifest.slot,
           slot != "face", slot != "clock", slot != "message-indicator" {
            specification.equipped[slot] = id
        }
        return specification
    }

    func statusSlotBinding(_ status: FishUserStatus, slot: String) -> Binding<String> {
        Binding(
            get: {
                guard let id = self.statusPreviewAccessorySpec(status).equipped[slot],
                      self.compatibleAccessories(slot: slot).contains(where: { $0.id == id }) else { return "" }
                return id
            },
            set: { value in
                var all = self.fishPreferences.statusAccessorySpecs ?? [:]
                var root = all[status.rawValue]?.objectValue ?? [:]
                var equipped = root["equipped"]?.objectValue
                    ?? AppearanceJSON.accessorySpec(in: self.draft, characterID: self.draft.pet.characterPackId)
                        .equipped.mapValues(JSONValue.string)
                equipped[slot] = .string(value)
                root["equipped"] = .object(equipped)
                all[status.rawValue] = .object(root)
                self.fishPreferences.statusAccessorySpecs = all
            }
        )
    }

    func statusAccessoryTuning(_ status: FishUserStatus, id: String, key: String, fallback: Double) -> Double {
        fishPreferences.statusAccessorySpecs?[status.rawValue]?.objectValue?["tuning"]?.objectValue?[id]?.objectValue?[key]?.numberValue ?? fallback
    }

    func setStatusAccessoryTuning(_ status: FishUserStatus, id: String, key: String, value: Double) {
        var all = fishPreferences.statusAccessorySpecs ?? [:]
        var root = all[status.rawValue]?.objectValue ?? [:]
        var tuning = root["tuning"]?.objectValue ?? [:]
        var item = tuning[id]?.objectValue ?? [:]
        item[key] = .number(value)
        tuning[id] = .object(item)
        root["tuning"] = .object(tuning)
        all[status.rawValue] = .object(root)
        fishPreferences.statusAccessorySpecs = all
    }

    func statusDIYValue(_ status: FishUserStatus, part: String, key: String, fallback: Double) -> Double {
        fishPreferences.statusCustomizations?[status.rawValue]?.objectValue?[part]?.objectValue?[key]?.numberValue ?? fallback
    }

    func setStatusDIYValue(_ status: FishUserStatus, part: String, key: String, value: Double) {
        var all = fishPreferences.statusCustomizations ?? [:]
        var specification = all[status.rawValue]?.objectValue
            ?? draft.pet.customization[draft.pet.characterPackId]?.objectValue
            ?? [:]
        var component = specification[part]?.objectValue ?? [:]
        component[key] = .number(value)
        specification[part] = .object(component)
        all[status.rawValue] = .object(specification)
        fishPreferences.statusCustomizations = all
    }

    func statusDIYShape(_ status: FishUserStatus, part: String) -> String {
        fishPreferences.statusCustomizations?[status.rawValue]?.objectValue?[part]?.objectValue?["shape"]?.stringValue
            ?? draft.pet.customization[draft.pet.characterPackId]?.objectValue?[part]?.objectValue?["shape"]?.stringValue
            ?? "default"
    }

    func setStatusDIYShape(_ status: FishUserStatus, part: String, id: String) {
        var all = fishPreferences.statusCustomizations ?? [:]
        var specification = all[status.rawValue]?.objectValue
            ?? draft.pet.customization[draft.pet.characterPackId]?.objectValue
            ?? [:]
        var component = specification[part]?.objectValue ?? [:]
        component["shape"] = .string(id)
        specification[part] = .object(component)
        all[status.rawValue] = .object(specification)
        fishPreferences.statusCustomizations = all
    }

    func unlockFishProfile() {
        guard let messengerService else { return }
        do {
            _ = try messengerService.unlockProfileInteractively(isEnglish: isEnglish)
            loadFishDrafts()
            refreshFishState()
            message = isEnglish ? "Fish identity is available." : "鱼鱼身份已恢复。"
        } catch {
            refreshFishState()
            message = isEnglish
                ? "Authorization was not completed. The existing identity was kept unchanged."
                : "未完成授权；现有身份保持不变。"
        }
    }

    func createFishProfile() {
        let name = fishDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = fishSetupToken
        guard let messengerService,
              messengerService.profileState == .notConfigured,
              !name.isEmpty, name.utf8.count <= 48,
              let relayURL = URL(string: fishRelayURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              relayURL.scheme == "https", relayURL.host != nil,
              relayURL.user == nil, relayURL.password == nil,
              relayURL.query == nil, relayURL.fragment == nil,
              (16...256).contains(token.utf8.count) else {
            fishIdentityStatus = isEnglish
                ? "Check the display name, HTTPS relay URL, and 16–256 character setup secret."
                : "请检查显示名称、HTTPS 中转地址和 16–256 字符的设置密钥。"
            return
        }
        fishSetupBusy = true
        fishIdentityStatus = isEnglish ? "Checking relay and creating identity…" : "正在验证中转并建立身份…"
        Task { @MainActor in
            defer { self.fishSetupBusy = false }
            do {
                try await messengerService.createProfile(displayName: name, relayURL: relayURL, setupToken: token)
                self.fishSetupToken = ""
                self.loadFishDrafts()
                self.refreshFishState()
                self.message = self.isEnglish ? "Fish identity created." : "鱼鱼身份已建立。"
            } catch {
                self.fishIdentityStatus = (self.isEnglish ? "Relay validation failed: " : "中转验证失败：")
                    + error.localizedDescription
            }
        }
    }

    func validateFishInvite() {
        let code = fishInviteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            fishInviteStatus = isEnglish ? "Paste a fish code first." : "请先粘贴鱼鱼码。"
            return
        }
        do {
            let invite = try FishInvite.decode(code)
            let ownInvite = fishInviteCode.isEmpty ? nil : (try? FishInvite.decode(fishInviteCode))
            if ownInvite?.publicKey == invite.publicKey {
                fishInviteStatus = isEnglish ? "This is your own fish code." : "这是你自己的鱼鱼码。"
            } else if fishContacts.contains(where: { $0.invite.publicKey == invite.publicKey }) {
                fishInviteStatus = isEnglish ? "This friend has already been added." : "这个好友已经添加过。"
            } else if let relay = messengerService?.profile?.relayURL, relay != invite.relayURL {
                fishInviteStatus = isEnglish
                    ? "Valid code, but it uses a different relay."
                    : "鱼鱼码有效，但中转站与当前身份不同。"
            } else {
                fishInviteStatus = isEnglish
                    ? "Valid fish code · \(invite.displayName)"
                    : "鱼鱼码有效 · \(invite.displayName)"
            }
        } catch {
            fishInviteStatus = isEnglish ? "Invalid or unsupported fish code." : "鱼鱼码无效或版本不受支持。"
        }
    }

    func addFishContact() {
        guard let messengerService, messengerService.profile != nil else {
            fishInviteStatus = isEnglish ? "Create your fish identity first." : "请先建立自己的鱼鱼身份。"
            return
        }
        do {
            try messengerService.addContact(code: fishInviteInput)
            fishInviteInput = ""
            fishInviteStatus = isEnglish ? "Friend added." : "好友已添加。"
            refreshFishState()
        } catch {
            fishInviteStatus = isEnglish ? "Could not add this fish code." : "无法添加这个鱼鱼码。"
        }
    }

    func copyFishInviteCode() {
        guard !fishInviteCode.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fishInviteCode, forType: .string)
        message = isEnglish ? "Fish code copied." : "鱼鱼码已复制。"
    }

    func reloadFromRuntime() {
        hideFishInviteCodeForWindowReopen()
        draft = runtime.config
        refreshClock()
        clockSoundDraft = ClockSoundPreferencesDraft(clockState.preferences)
        loadFishDrafts()
        refreshFishState()
        refreshIntegrations()
    }

    func mergeQuickSettingsFromRuntime() {
        draft = QuickSettingsDraftMerge.merge(runtime: runtime.config, into: draft)
    }

    func refreshIntegrations() {
        for provider in ["codex", "claude"] {
            integrationBusy.insert(provider)
            integrationManager.inspect(provider) { [weak self] status in
                self?.integrationStatuses[provider] = status
                self?.integrationBusy.remove(provider)
            }
        }
    }

    func connectIntegration(_ provider: String) {
        integrationBusy.insert(provider)
        integrationManager.connect(provider) { [weak self] result in
            guard let self else { return }
            self.integrationBusy.remove(provider)
            switch result {
            case .success(let status):
                self.integrationStatuses[provider] = status
                self.message = provider == "codex"
                    ? (self.isEnglish ? "Installed. Allow the pet in Codex /hooks, then continue a task." : "已安装。请在 Codex 的 /hooks 允许水滴鱼，然后继续一次任务。")
                    : (self.isEnglish ? "Installed. Restart Claude Code and continue a task." : "已安装。重新打开 Claude Code，然后继续一次任务。")
            case .failure(let error):
                self.message = (self.isEnglish ? "Connection failed: " : "连接失败：") + error.localizedDescription
            }
        }
    }

    func checkUpdate() {
        updateStatus = isEnglish ? "Checking the native release channel…" : "正在检查原生版更新…"
        updateProgress = 0
        updater.check { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.upToDate(let version)):
                self.availableUpdate = nil; self.updateProgress = nil
                self.updateAvailable = false
                self.updateStatus = self.isEnglish ? "Native v\(version) is up to date." : "原生版 v\(version) 已是最新。"
            case .success(.available(let manifest, let asset)):
                self.availableUpdate = (manifest, asset); self.updateProgress = nil
                self.updateAvailable = true
                self.updateStatus = self.isEnglish ? "Native v\(manifest.version) is ready." : "发现原生版 v\(manifest.version)，可以安装。"
            case .failure(let error):
                self.availableUpdate = nil; self.updateProgress = nil
                self.updateAvailable = false
                self.updateStatus = error.localizedDescription
            }
        }
    }

    func installUpdate() {
        guard let update = availableUpdate else { return }
        updateProgress = 0.05
        updateStatus = isEnglish ? "Downloading and verifying…" : "正在下载并校验…"
        updater.install(manifest: update.0, asset: update.1, progress: { [weak self] value in
            self?.updateProgress = value
        }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let url):
                self.updateStatus = self.isEnglish ? "Installed. Restarting…" : "安装完成，正在重新打开…"
                self.updater.relaunch(at: url) { error in
                    DispatchQueue.main.async {
                        if let error { self.updateStatus = (self.isEnglish ? "Could not restart: " : "无法重新打开：") + error.localizedDescription }
                        else { NSApp.terminate(nil) }
                    }
                }
            case .failure(let error): self.updateProgress = nil; self.updateStatus = error.localizedDescription
            }
        }
    }

    func startTimer() {
        do { try clockService?.startTimer(minutes: timerMinutes, label: timerLabel); refreshClock() }
        catch { message = String(describing: error) }
    }

    func pauseOrResumeTimer() {
        do {
            if clockState.timer?.state == "running" { try clockService?.pauseTimer() } else { try clockService?.resumeTimer() }
            refreshClock()
        } catch { message = String(describing: error) }
    }

    func extendTimer() { do { try clockService?.extendTimer(); refreshClock() } catch { message = String(describing: error) } }
    func cancelTimer() { do { try clockService?.cancelTimer(); refreshClock() } catch { message = String(describing: error) } }

    func createAlarm() {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        do {
            try clockService?.createAlarm(
                label: alarmLabel, mode: alarmMode, time: alarmTime,
                date: alarmMode == "once" ? formatter.string(from: alarmDate) : nil,
                weekdays: alarmMode == "weekly" ? [1, 2, 3, 4, 5] : []
            )
            refreshClock()
        } catch { message = String(describing: error) }
    }

    func toggleAlarm(_ alarm: ClockState.Alarm, enabled: Bool) {
        do { try clockService?.setAlarmEnabled(id: alarm.id, enabled: enabled); refreshClock() }
        catch { message = String(describing: error) }
    }

    func deleteAlarm(_ alarm: ClockState.Alarm) {
        do { try clockService?.deleteAlarm(id: alarm.id); refreshClock() }
        catch { message = String(describing: error) }
    }

    func saveClockPreferences() {
        guard let clockService else {
            message = isEnglish ? "Alarm clock settings are unavailable." : "闹钟设置暂时不可用。"
            return
        }
        do {
            try clockService.updatePreferences(clockSoundDraft.applying(to: clockService.state.preferences))
            refreshClock()
            clockSoundDraft = ClockSoundPreferencesDraft(clockState.preferences)
        } catch {
            message = String(describing: error)
        }
    }

    func selectAlarmAccessory(_ id: String) {
        guard let clockService else {
            message = isEnglish ? "Alarm clock settings are unavailable." : "闹钟设置暂时不可用。"
            return
        }
        var preferences = clockService.state.preferences
        preferences.alarmAccessoryID = ClockAccessoryStyle.normalized(id)
        do {
            try clockService.updatePreferences(preferences)
            refreshClock()
            message = isEnglish ? "Clock appearance saved." : "闹钟外观已保存。"
        } catch {
            refreshClock()
            message = (isEnglish ? "Could not save clock appearance: " : "无法保存闹钟外观：") + error.localizedDescription
        }
    }

    func dismissClockAlerts() { do { try clockService?.dismissAlerts(); refreshClock() } catch { message = String(describing: error) } }

    func previewSound(_ id: String) { soundPlayer.play(id: id) }

    func workdayBinding(_ day: Int) -> Binding<Bool> {
        Binding(
            get: { self.draft.schedule.workdays.contains(day) },
            set: { enabled in
                if enabled {
                    if !self.draft.schedule.workdays.contains(day) { self.draft.schedule.workdays.append(day) }
                } else {
                    self.draft.schedule.workdays.removeAll { $0 == day }
                }
                self.draft.schedule.workdays.sort()
            }
        )
    }

    func refreshClock() { clockState = clockService?.state ?? .empty }

    var isEnglish: Bool { draft.ui.locale == "en" }

    func apply() {
        do {
            let previousLaunchAtLogin = runtime.config.startup.launchAtLogin
            let desiredLaunchAtLogin = draft.startup.launchAtLogin
            if previousLaunchAtLogin == desiredLaunchAtLogin {
                try runtime.update { $0 = draft }
            } else {
                try LoginItemSettingTransaction.apply(
                    previous: previousLaunchAtLogin,
                    desired: desiredLaunchAtLogin,
                    updateSystem: { try LoginItemController.sync(enabled: $0) },
                    saveConfiguration: { [runtime, draft] _ in try runtime.update { $0 = draft } }
                )
            }
            draft = runtime.config
            message = isEnglish ? "Saved." : "已保存。"
            onApply()
        } catch {
            message = (isEnglish ? "Could not save: " : "无法保存：") + String(describing: error)
        }
    }

    func reset() {
        draft = .defaults
        message = isEnglish ? "Defaults restored in this window. Select Apply to save." : "已在当前窗口恢复默认值，点“应用”后保存。"
    }

    func diyValue(part: String, key: String, fallback: Double) -> Double {
        let character = draft.pet.characterPackId
        return draft.pet.customization[character]?.objectValue?[part]?.objectValue?[key]?.numberValue ?? fallback
    }

    func setDIYValue(part: String, key: String, value: Double) {
        let character = draft.pet.characterPackId
        var specification = draft.pet.customization[character]?.objectValue ?? [:]
        var component = specification[part]?.objectValue ?? [:]
        component[key] = .number(value)
        specification[part] = .object(component)
        draft.pet.customization[character] = .object(specification)
    }

    func diyShape(part: String) -> String {
        let character = draft.pet.characterPackId
        return draft.pet.customization[character]?.objectValue?[part]?.objectValue?["shape"]?.stringValue ?? "default"
    }

    func setDIYShape(part: String, id: String) {
        let character = draft.pet.characterPackId
        var specification = draft.pet.customization[character]?.objectValue ?? [:]
        var component = specification[part]?.objectValue ?? [:]
        component["shape"] = .string(id)
        specification[part] = .object(component)
        draft.pet.customization[character] = .object(specification)
    }

    func accessoryTuning(id: String, key: String, fallback: Double) -> Double {
        let character = draft.pet.characterPackId
        let root = draft.pet.accessories[character]?.objectValue
        return root?["tuning"]?.objectValue?[id]?.objectValue?[key]?.numberValue ?? fallback
    }

    func setAccessoryTuning(id: String, key: String, value: Double) {
        let character = draft.pet.characterPackId
        var root = draft.pet.accessories[character]?.objectValue ?? [:]
        var allTuning = root["tuning"]?.objectValue ?? [:]
        var tuning = allTuning[id]?.objectValue ?? [:]
        tuning[key] = .number(value)
        allTuning[id] = .object(tuning)
        root["tuning"] = .object(allTuning)
        if root["equipped"] == nil { root["equipped"] = .object([:]) }
        draft.pet.accessories[character] = .object(root)
    }

    func selectCharacter(_ id: String) {
        draft.pet.characterPackId = id
        let compatible = languages.filter { isLanguage($0, compatibleWith: id) }
        if !compatible.contains(where: { $0.id == draft.language.packId }) {
            draft.language.packId = characters.first(where: { $0.id == id })?.manifest.defaultLanguagePack
                ?? compatible.first?.id
                ?? AppConfig.defaults.language.packId
        }
    }

    var compatibleLanguages: [LanguagePack] {
        languages.filter { isLanguage($0, compatibleWith: draft.pet.characterPackId) }
    }

    var selectedCharacter: CharacterPack? {
        characters.first(where: { $0.id == draft.pet.characterPackId })
    }

    func compatibleAccessories(slot: String) -> [AccessoryPack] {
        CharacterExpressionCompatibility.accessories(
            accessories, compatibleWith: selectedCharacter, slot: slot
        )
    }

    private func isLanguage(_ language: LanguagePack, compatibleWith characterID: String) -> Bool {
        if let ids = language.manifest.characterPackIds { return ids.contains(characterID) }
        return characterID == "grass-buddy"
            ? language.id.hasPrefix("grass-buddy-")
            : language.id.hasPrefix("blobfish-")
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case character, friends, schedule, language, connection, clocks, performance
    var id: String { rawValue }
}

enum SettingsSurfacePalette {
    static var windowBackground: Color { Color(nsColor: .windowBackgroundColor) }
    static var controlBackground: Color { Color(nsColor: .controlBackgroundColor) }
    static var previewBackground: Color { Color(nsColor: .textBackgroundColor) }
    static var separator: Color { Color(nsColor: .separatorColor) }
    static var subtleFill: Color { Color(nsColor: .quaternaryLabelColor) }

    // Keep this list beside the SwiftUI tokens so the native self-check can
    // verify that every settings surface still resolves through AppKit's
    // light/dark appearance system instead of a fixed light color.
    static var adaptiveNativeColors: [NSColor] {
        [
            .windowBackgroundColor,
            .controlBackgroundColor,
            .textBackgroundColor,
            .separatorColor,
            .quaternaryLabelColor,
        ]
    }
}

struct BrandedSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        HStack(spacing: 0) {
            brandedSidebar
            VStack(spacing: 0) {
                Group {
                    if model.selectedSection == .character {
                        characterWorkspace
                    } else {
                        ScrollView { section.padding(18).frame(maxWidth: 680, alignment: .leading) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                Divider()
                HStack {
                    Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Button(model.isEnglish ? "Reset" : "恢复默认") { model.reset() }
                    Button(model.isEnglish ? "Apply" : "应用") { model.apply() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            }
            .frame(minWidth: 576, minHeight: 540)
        }
        .frame(minWidth: 760, minHeight: 540)
        .background(SettingsSurfacePalette.windowBackground)
    }

    private var brandedSidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 5) {
                Text("DESKTOP PET").font(.caption.weight(.bold)).tracking(2.2).foregroundStyle(Color(red: 0.28, green: 0.48, blue: 0.47))
                Text(currentCharacter?.manifest.displayName ?? t("水滴鱼", "Blobfish"))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text(t("陪你工作，也记得喘口气。", "A quiet companion for focused work."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 10)

            sidebarButton(.character, "person.crop.circle", zh: "角色与动作", en: "Character & Motion")
            sidebarButton(.friends, "person.2.wave.2", zh: "传话与串门", en: "Messages & Visits")
            sidebarButton(.schedule, "clock", zh: "问候与作息", en: "Schedule & Greetings")
            sidebarButton(.language, "quote.bubble", zh: "台词", en: "Dialogue")
            sidebarButton(.connection, "link", zh: "连接与隐私", en: "Connections & Privacy")
            sidebarButton(.clocks, "timer", zh: "闹钟与计时器", en: "Alarms & Timers")
            sidebarButton(.performance, "gauge.with.dots.needle.33percent", zh: "性能与更新", en: "Performance & Updates")
            Spacer()
            Text("NATIVE PREVIEW · " + model.updater.currentVersion)
                .font(.caption2.monospaced()).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 184)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.thinMaterial)
        .overlay(alignment: .trailing) { Divider() }
    }

    private func sidebarButton(_ section: SettingsSection, _ icon: String, zh: String, en: String) -> some View {
        Button {
            model.selectedSection = section
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).frame(width: 18)
                Text(t(zh, en)).fontWeight(.semibold)
                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .leading)
            .contentShape(Rectangle())
            .foregroundStyle(model.selectedSection == section ? Color.white : Color.primary.opacity(0.72))
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(model.selectedSection == section ? Color(red: 0.28, green: 0.48, blue: 0.47) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var section: some View {
        switch model.selectedSection {
        case .character: EmptyView()
        case .friends: friendsSection
        case .schedule: scheduleSection
        case .language: languageSection
        case .connection: connectionSection
        case .clocks: clocksSection
        case .performance: performanceSection
        }
    }

    private var friendsSection: some View {
        SettingsPage(
            title: t("传话与串门", "Messages & Visits"),
            subtitle: t("身份与好友码在这里设置；对话记录请从右键“消息”打开。", "Configure identity and fish codes here; open conversations from Messages in the context menu.")
        ) {
            fishIdentityCard
            fishProfileCard
            fishStatusAppearanceCard
            fishInviteCard
        }
    }

    private var fishIdentityCard: some View {
        SettingsCard {
            HStack {
                Text(t("鱼鱼身份", "Fish identity")).font(.headline)
                Spacer()
                Label(model.fishIdentityStatus, systemImage: model.fishInviteCode.isEmpty ? "key.slash" : "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(model.fishInviteCode.isEmpty ? Color.secondary : Color.green)
            }
            if model.messengerService?.profileState == .notConfigured {
                LabeledContent(t("显示名称", "Display name")) {
                    TextField("", text: $model.fishDisplayName).textFieldStyle(.roundedBorder)
                }
                LabeledContent(t("中转地址", "Relay URL")) {
                    TextField("https://relay.example.com", text: $model.fishRelayURL).textFieldStyle(.roundedBorder)
                }
                LabeledContent(t("设置密钥", "Setup secret")) {
                    SecureField("", text: $model.fishSetupToken).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text(t("私钥只保存在系统钥匙串，不会在界面显示。", "The private key stays in Keychain and is never shown here."))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if model.fishSetupBusy { ProgressView().controlSize(.small) }
                    Button(t("验证并建立", "Verify & create")) { model.createFishProfile() }
                        .disabled(model.fishSetupBusy)
                }
            } else if model.messengerService?.profileState == .available {
                LabeledContent(t("中转站", "Relay")) {
                    Text(model.messengerService?.profile?.relayURL.host ?? "—")
                        .textSelection(.enabled)
                }
                if let displayedCode = model.displayedFishInviteCode {
                    Text(t("我的鱼鱼码", "My fish code")).font(.subheadline.weight(.semibold))
                    HStack(alignment: .top) {
                        Text(displayedCode)
                            .font(.caption.monospaced())
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        Button(
                            model.fishInviteCodeRevealed
                                ? t("隐藏完整鱼鱼码", "Hide full fish code")
                                : t("显示完整鱼鱼码", "Show full fish code")
                        ) { model.toggleFishInviteCodeReveal() }
                        Button(t("复制", "Copy")) { model.copyFishInviteCode() }
                    }
                    Text(t("鱼鱼码包含向你投递消息的权限，只发给你信任的人。", "A fish code grants permission to deliver messages to you; share it only with people you trust."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(t(
                    "水滴鱼启动时不会再主动弹出电脑密码。只有你点击下方按钮，系统才会请求读取现有身份；取消不会删除或重建私钥。",
                    "Blobfish no longer requests your computer password at launch. The system asks only after you click below; cancelling never deletes or replaces the private key."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                if model.messengerService?.profileState == .authorizationRequired
                    || model.messengerService?.profileState == .locked {
                    Button(t("授权读取现有身份", "Authorize existing identity")) {
                        model.unlockFishProfile()
                    }
                }
            }
        }
    }

    private var fishProfileCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                Text(t("消息与串门偏好", "Message & visit preferences")).font(.headline)
                TextField(t("显示名称", "Display name"), text: $model.fishDisplayName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.messengerService?.profile == nil)
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("普通傳話提示", "Message alerts")).font(.subheadline.weight(.semibold))
                    HStack {
                        Toggle(t("郵箱", "Mailbox"), isOn: Binding(
                            get: { model.fishPreferences.effectiveMessageShowsMailbox },
                            set: { model.fishPreferences.messageShowsMailbox = $0 }
                        ))
                        Toggle(t("氣泡", "Bubble"), isOn: Binding(
                            get: { model.fishPreferences.effectiveMessageShowsBubble },
                            set: { model.fishPreferences.messageShowsBubble = $0 }
                        ))
                    }
                    Text(t("串門聊天提示", "Visit chat alerts")).font(.subheadline.weight(.semibold))
                    HStack {
                        Toggle(t("郵箱", "Mailbox"), isOn: Binding(
                            get: { model.fishPreferences.effectiveVisitShowsMailbox },
                            set: { model.fishPreferences.visitShowsMailbox = $0 }
                        ))
                        Toggle(t("氣泡", "Bubble"), isOn: Binding(
                            get: { model.fishPreferences.effectiveVisitShowsBubble },
                            set: { model.fishPreferences.visitShowsBubble = $0 }
                        ))
                    }
                    Text(t("兩項可以同時開啟，也可以全部關閉。", "Both options may be enabled together or disabled."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker(t("消息气泡", "Message bubble"), selection: $model.fishPreferences.bubbleColor) {
                    Text(t("海水蓝", "Ocean blue")).tag("#1F7AE8")
                    Text(t("珊瑚粉", "Coral pink")).tag("#E65D83")
                    Text(t("海草绿", "Seaweed green")).tag("#2B9C77")
                    Text(t("葡萄紫", "Grape purple")).tag("#7957C8")
                    Text(t("夜空黑", "Night black")).tag("#384052")
                }
                }
                Toggle(t("允许好友串门", "Allow friend visits"), isOn: $model.fishPreferences.visitsEnabled)
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("魚魚互動音效", "Fish interaction sounds"))
                        .font(.subheadline.weight(.semibold))
                    ForEach(FishRemoteInteraction.allCases) { interaction in
                        HStack(spacing: 8) {
                            Toggle(
                                interaction.title(isEnglish: model.isEnglish),
                                isOn: model.interactionSoundEnabledBinding(interaction)
                            )
                            Spacer(minLength: 6)
                            soundPicker(selection: model.interactionSoundBinding(interaction))
                                .frame(width: 125)
                                .disabled(!model.fishPreferences.soundEnabled(for: interaction))
                            Button(t("試聽", "Preview")) {
                                model.previewSound(model.fishPreferences.soundID(for: interaction))
                            }
                            .disabled(!model.fishPreferences.soundEnabled(for: interaction))
                        }
                    }
                    Text(t(
                        "所有魚魚互動同等播放，不受勿擾、設定視窗或輸入狀態攔截；新動畫會取代正在播放的動畫。",
                        "All fish interactions play equally, including during Do Not Disturb, settings, or typing; a new animation replaces the current one."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("魚魚傳話快捷互動", "Message quick actions"))
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { index in
                            Picker(
                                t("快捷 \(index + 1)", "Shortcut \(index + 1)"),
                                selection: model.quickInteractionBinding(at: index)
                            ) {
                                ForEach(FishRemoteInteraction.allCases) { interaction in
                                    Label(
                                        interaction.title(isEnglish: model.isEnglish),
                                        systemImage: interaction.symbolName
                                    )
                                    .tag(interaction)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Text(t(
                        "傳話框只顯示這三個快捷鍵；完整互動仍可從魚魚右鍵選單使用。",
                        "Only these three appear in the message window; all actions remain in the fish right-click menu."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Picker(t("消息停留时间", "Message dwell time"), selection: Binding(
                    get: { model.fishPreferences.messageDisplaySeconds ?? 20 },
                    set: { model.fishPreferences.messageDisplaySeconds = $0 }
                )) {
                    Text(t("10 秒", "10 sec")).tag(10.0)
                    Text(t("20 秒", "20 sec")).tag(20.0)
                    Text(t("30 秒", "30 sec")).tag(30.0)
                    Text(t("60 秒", "60 sec")).tag(60.0)
                }
                .pickerStyle(.segmented)
                Text(t("每条消息独立计时；新消息会顶开旧消息，不会覆盖。", "Each message has its own timer; new messages push older ones aside instead of replacing them."))
                    .font(.caption).foregroundStyle(.secondary)
                visualStylePicker(
                    title: t("未读消息提示", "Unread message indicator"),
                    ids: FishMessageIndicatorStyle.ids,
                    selection: Binding(
                        get: { model.fishPreferences.effectiveMessageIndicatorID },
                        set: { model.fishPreferences.messageIndicatorID = $0 }
                    )
                )
                Toggle(t("好友来信播放音效", "Play sound for friend messages"), isOn: $model.fishPreferences.incomingSoundEnabled)
                if model.fishPreferences.incomingSoundEnabled {
                    HStack {
                        soundPicker(selection: $model.fishPreferences.incomingSoundID)
                        Button(t("试听", "Preview")) { model.previewSound(model.fishPreferences.incomingSoundID) }
                    }
                }
                Button(t("保存鱼友设置", "Save fish settings")) { model.saveFishSettings() }
            }
        }
    }

    private var fishInviteCard: some View {
        SettingsCard {
            HStack {
                Text(t("添加好友", "Add a friend")).font(.headline)
                Spacer()
                Text(model.isEnglish ? "\(model.fishContacts.count) friends" : "\(model.fishContacts.count) 位好友")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField(t("粘贴对方的鱼鱼码", "Paste a friend's fish code"), text: $model.fishInviteInput)
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.fishInviteInput) { value in
                    if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        model.validateFishInvite()
                    }
                }
            HStack {
                Text(model.fishInviteStatus)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel(t("鱼鱼码检查结果", "Fish code validation result"))
                Spacer()
                Button(t("检查", "Check")) { model.validateFishInvite() }
                Button(t("添加", "Add")) { model.addFishContact() }
                    .disabled(model.messengerService?.profile == nil || model.fishInviteInput.isEmpty)
            }
            if !model.fishContacts.isEmpty {
                Divider()
                ForEach(model.fishContacts) { contact in
                    HStack {
                        Image(systemName: contact.blocked ? "nosign" : contact.muted ? "speaker.slash" : "fish")
                        Text(contact.nickname ?? contact.invite.displayName)
                        Spacer()
                        Text(contact.blocked ? t("已封锁", "Blocked") : contact.muted ? t("已静音", "Muted") : t("可传话", "Ready"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var fishStatusAppearanceCard: some View {
        SettingsCard {
            Text(t("狀態外觀", "Status appearance")).font(.headline)
            Text(t("每個狀態可指定表情與一件裝飾；串門時好友會看到。", "Choose a face and one decoration per status; visiting friends see them too."))
                .font(.caption).foregroundStyle(.secondary)
            Picker(t("預覽狀態", "Preview status"), selection: $model.fishStatusPreview) {
                ForEach(FishUserStatus.allCases) { status in
                    Text("\(status.emoji) \(status.title(isEnglish: model.isEnglish))").tag(status)
                }
            }
            .pickerStyle(.segmented)
            PetAppearancePreview(
                character: currentCharacter,
                scale: min(1, model.draft.pet.scale),
                accessories: model.accessories,
                accessorySpec: model.statusPreviewAccessorySpec(model.fishStatusPreview),
                customization: model.draft.pet.customization[model.draft.pet.characterPackId],
                moodFaceID: model.fishPreferences.faceID(for: model.fishStatusPreview),
                showsAlarmClock: false
            )
            .frame(height: 125)
            .background(SettingsSurfacePalette.previewBackground, in: RoundedRectangle(cornerRadius: 12))
            let status = model.fishStatusPreview
            Text("\(status.emoji) \(status.title(isEnglish: model.isEnglish)) · \(t("細節 DIY", "Detailed DIY"))")
                .font(.subheadline.weight(.semibold))
            Picker(t("表情", "Expression"), selection: model.statusFaceBinding(status)) {
                Text(t("無表情", "No expression")).tag("")
                ForEach(model.compatibleAccessories(slot: "face")) { accessory in
                    Text(accessory.manifest.displayName).tag(accessory.id)
                }
            }
            ForEach(["hat", "eyewear", "hand"], id: \.self) { slot in
                VStack(alignment: .leading, spacing: 6) {
                    Picker(slotName(slot), selection: model.statusSlotBinding(status, slot: slot)) {
                        Text(t("不使用", "None")).tag("")
                        ForEach(model.compatibleAccessories(slot: slot)) { accessory in
                            Text(accessory.manifest.displayName).tag(accessory.id)
                        }
                    }
                    if let id = model.statusPreviewAccessorySpec(status).equipped[slot], !id.isEmpty {
                        statusAccessoryTuningEditor(status, id: id)
                    }
                }
            }
            Button(t("保存狀態外觀", "Save status appearance")) { model.saveFishSettings() }
        }
    }

    private func deliveryPresentationButton(id: String, title: String, icon: String) -> some View {
        let selected = (model.fishPreferences.showsIncomingBubble ? "bubble" : "mail") == id
        return Button {
            model.fishPreferences.deliveryPresentation = id
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selected ? "checkmark.circle.fill" : icon)
                Text(title)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? Color.accentColor : SettingsSurfacePalette.subtleFill, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func statusAccessoryTuningEditor(_ status: FishUserStatus, id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(["size", "width", "height", "offsetX", "offsetY"], id: \.self) { key in
                let range: ClosedRange<Double> = key == "offsetX" || key == "offsetY" ? -30...30 : 0.4...2
                let fallback = key == "offsetX" || key == "offsetY" ? 0.0 : 1.0
                LabeledContent(key) {
                    Slider(value: Binding(
                        get: { model.statusAccessoryTuning(status, id: id, key: key, fallback: fallback) },
                        set: { model.setStatusAccessoryTuning(status, id: id, key: key, value: $0) }
                    ), in: range)
                }
            }
        }
        .padding(.leading, 14)
    }

    private var currentCharacter: CharacterPack? {
        model.characters.first { $0.id == model.draft.pet.characterPackId }
    }

    private var characterWorkspace: some View {
        HStack(alignment: .top, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                Text(t("角色与动作", "Character & Motion"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(t("左边实时看效果，右边慢慢捏。", "Preview on the left while you tune on the right."))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    PetAppearancePreview(
                        character: currentCharacter,
                        scale: model.draft.pet.scale,
                        accessories: model.accessories,
                        accessorySpec: AppearanceJSON.accessorySpec(
                            in: model.draft,
                            characterID: model.draft.pet.characterPackId
                        ),
                        customization: model.draft.pet.customization[model.draft.pet.characterPackId],
                        alarmClockAccessoryID: model.clockState.preferences.effectiveAlarmAccessoryID
                    )
                    .frame(width: 220, height: 140)
                    Text(currentCharacter?.manifest.displayName ?? t("角色预览", "Character preview"))
                        .font(.headline)
                    Text(t("拖动滑杆会立即反映在这里", "Changes appear here immediately"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(SettingsSurfacePalette.previewBackground, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(SettingsSurfacePalette.separator))

                Picker(t("角色", "Character"), selection: Binding(
                    get: { model.draft.pet.characterPackId },
                    set: { model.selectCharacter($0) }
                )) {
                    ForEach(model.characters) { Text($0.manifest.displayName).tag($0.id) }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 10) {
                    Text(t("大小", "Size")).font(.subheadline.weight(.semibold))
                    HStack {
                        Slider(value: $model.draft.pet.scale, in: 0.65...1.5, step: 0.05)
                        Text(model.draft.pet.scale.formatted(.number.precision(.fractionLength(2)))).monospacedDigit()
                    }
                    Text(t("游动速度", "Movement speed")).font(.subheadline.weight(.semibold))
                    HStack {
                        Slider(value: $model.draft.pet.speed, in: 0.25...4, step: 0.25)
                        Text(model.draft.pet.speed.formatted(.number.precision(.fractionLength(2)))).monospacedDigit()
                    }
                    Picker(t("游动方向", "Movement axis"), selection: $model.draft.pet.moveAxis) {
                        Text(t("左右", "Horizontal")).tag("horizontal")
                        Text(t("上下", "Vertical")).tag("vertical")
                    }.pickerStyle(.segmented)
                    Toggle(t("有任务时游动", "Move while tasks are active"), isOn: $model.draft.pet.roamWhenTasks)
                    Toggle(t("没有任务时也游动", "Move while idle"), isOn: $model.draft.pet.roamWhenNoTasks)
                    Toggle(t("撞击反弹后翻转鱼鱼", "Flip fish after bouncing"), isOn: $model.draft.pet.flipOnBounce)
                }
                .padding(12)
                .background(SettingsSurfacePalette.controlBackground, in: RoundedRectangle(cornerRadius: 14))
                }
                .frame(width: 254, alignment: .topLeading)
            }
            .frame(width: 254)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsCard {
                        Text(currentCharacter?.id == "grass-buddy" ? t("捏草", "Shape the grass") : t("捏鱼", "Shape the fish"))
                            .font(.title3.weight(.bold))
                        Text(t("形状、五官和手脚会同步出现在左侧预览。", "Shape, face and limbs update in the live preview."))
                            .font(.callout).foregroundStyle(.secondary)
                        diyEditor
                    }
                    SettingsCard {
                        Text(t("饰品", "Accessories")).font(.title3.weight(.bold))
                        accessoryEditors
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
    }

    private var accessoryEditors: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(["face", "hat", "eyewear", "hand"], id: \.self) { slot in
                Picker(slotName(slot), selection: accessoryBinding(slot: slot)) {
                    Text(t("不使用", "None")).tag("")
                    ForEach(model.compatibleAccessories(slot: slot)) { accessory in
                        Text(accessory.manifest.displayName).tag(accessory.id)
                    }
                }
                if let id = AppearanceJSON.accessorySpec(
                    in: model.draft,
                    characterID: model.draft.pet.characterPackId
                ).equipped[slot], slot != "face" {
                    accessoryTuningEditor(id: id)
                }
            }
            Divider()
            visualStylePicker(
                title: t("闹钟样式", "Alarm clock style"),
                ids: ClockAccessoryStyle.ids,
                selection: Binding(
                    get: { model.clockState.preferences.effectiveAlarmAccessoryID },
                    set: { model.selectAlarmAccessory($0) }
                )
            )
            Text(t("样式会立即保存；位置与大小请点下方的“应用”保存。", "The style saves immediately; use Apply below to save its size and position."))
                .font(.caption).foregroundStyle(.secondary)
            accessoryTuningEditor(id: model.clockState.preferences.effectiveAlarmAccessoryID)
        }
    }

    private var diyEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let manifest = model.characters.first(where: { $0.id == model.draft.pet.characterPackId })?.manifest,
               manifest.diy?.enabled == true {
                ForEach(["body", "fins"], id: \.self) { part in
                    if let shapes = manifest.diy?.shapes?[part], !shapes.isEmpty {
                        Picker(part == "body" ? t("身体形状", "Body shape") : t("手 / 鱼鳍形状", "Arm / fin shape"), selection: diyShapeBinding(part: part)) {
                            ForEach(shapes, id: \.id) { Text($0.label).tag($0.id) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                diySlider(t("身体胖瘦", "Body width"), part: "body", key: "width", range: 0.7...1.3, fallback: 1)
                diySlider(t("身体高矮", "Body height"), part: "body", key: "height", range: 0.7...1.3, fallback: 1)
                diySlider(t("手 / 鱼鳍大小", "Arm / fin size"), part: "fins", key: "size", range: 0.5...1.6, fallback: 1)
                diySlider(t("手 / 鱼鳍左右", "Arm / fin horizontal"), part: "fins", key: "offsetX", range: -16...16, fallback: 0)
                diySlider(t("手 / 鱼鳍上下", "Arm / fin vertical"), part: "fins", key: "offsetY", range: -16...16, fallback: 0)
                diySlider(t("眼睛大小", "Eye size"), part: "eyes", key: "size", range: 0.6...1.6, fallback: 1)
                }
                VStack(alignment: .leading, spacing: 12) {
                diySlider(t("眼睛间距", "Eye spacing"), part: "eyes", key: "spacing", range: -12...12, fallback: 0)
                diySlider(t("眼睛上下", "Eye vertical"), part: "eyes", key: "offsetY", range: -14...14, fallback: 0)
                diySlider(t("嘴巴大小", "Mouth size"), part: "mouth", key: "size", range: 0.6...1.5, fallback: 1)
                diySlider(t("嘴巴上下", "Mouth vertical"), part: "mouth", key: "offsetY", range: -14...14, fallback: 0)
                diySlider(t("鼻子大小", "Nose size"), part: "nose", key: "size", range: 0.6...1.6, fallback: 1)
                diySlider(t("鼻子上下", "Nose vertical"), part: "nose", key: "offsetY", range: -14...14, fallback: 0)
                }
            } else {
                Text(t("这个角色不支持捏制。", "This character does not support editing.")).foregroundStyle(.secondary)
            }
        }
    }

    private func diySlider(_ title: String, part: String, key: String, range: ClosedRange<Double>, fallback: Double) -> some View {
        LabeledContent(title) {
            Slider(value: Binding(
                get: { model.diyValue(part: part, key: key, fallback: fallback) },
                set: { model.setDIYValue(part: part, key: key, value: $0) }
            ), in: range)
        }
    }

    private func diyShapeBinding(part: String) -> Binding<String> {
        Binding(get: { model.diyShape(part: part) }, set: { model.setDIYShape(part: part, id: $0) })
    }

    private func accessoryBinding(slot: String) -> Binding<String> {
        Binding(
            get: {
                let id = AppearanceJSON.accessorySpec(
                    in: model.draft,
                    characterID: model.draft.pet.characterPackId
                ).equipped[slot] ?? ""
                if slot == "face" {
                    return CharacterExpressionCompatibility.resolveFaceID(
                        id, for: model.selectedCharacter, accessories: model.accessories
                    ) ?? ""
                }
                guard model.compatibleAccessories(slot: slot).contains(where: { $0.id == id }) else { return "" }
                return id
            },
            set: {
                AppearanceJSON.replacingAccessory(
                    in: &model.draft,
                    characterID: model.draft.pet.characterPackId,
                    slot: slot,
                    accessoryID: $0.isEmpty ? nil : $0
                )
            }
        )
    }

    private func accessoryTuningEditor(id: String) -> some View {
        let horizontalRange = AccessoryTuningLimits.horizontal(for: id)
        let verticalRange = AccessoryTuningLimits.vertical(for: id)
        return VStack(alignment: .leading, spacing: 6) {
            accessorySlider(t("大小", "Size"), id: id, key: "size", range: 0.4...2, fallback: 1)
            if !AccessoryTuningLimits.isClock(id) {
                accessorySlider(t("宽度", "Width"), id: id, key: "width", range: 0.5...1.8, fallback: 1)
                accessorySlider(t("高度", "Height"), id: id, key: "height", range: 0.5...1.8, fallback: 1)
            }
            accessorySlider(t("左右", "Horizontal"), id: id, key: "offsetX", range: horizontalRange, fallback: 0)
            accessorySlider(t("上下", "Vertical"), id: id, key: "offsetY", range: verticalRange, fallback: 0)
        }
        .padding(.leading, 18)
    }

    private func accessorySlider(_ title: String, id: String, key: String, range: ClosedRange<Double>, fallback: Double) -> some View {
        LabeledContent(title) {
            Slider(value: Binding(
                get: { model.accessoryTuning(id: id, key: key, fallback: fallback) },
                set: { model.setAccessoryTuning(id: id, key: key, value: $0) }
            ), in: range)
        }
    }

    private func slotName(_ slot: String) -> String {
        let names = model.isEnglish
            ? ["face": "Expression", "hat": "Hat", "eyewear": "Eyewear", "hand": "Hand"]
            : ["face": "表情", "hat": "头顶", "eyewear": "眼镜", "hand": "手边"]
        return names[slot] ?? slot
    }

    private var scheduleSection: some View {
        SettingsPage(title: t("问候与作息", "Schedule & Greetings"), subtitle: t("时间使用 24 小时制。", "Times use the 24-hour clock.")) {
            SettingsCard {
                Text(t("工作日", "Workdays")).font(.headline)
                HStack(spacing: 8) {
                    ForEach(Array(zip([1, 2, 3, 4, 5, 6, 0], model.isEnglish
                        ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                        : ["一", "二", "三", "四", "五", "六", "日"])), id: \.0) { day, label in
                        Toggle(label, isOn: model.workdayBinding(day))
                            .toggleStyle(.button)
                            .buttonStyle(.bordered)
                    }
                }
                TextField(t("午饭时间", "Lunch time"), text: $model.draft.schedule.lunchTime)
                TextField(t("下班时间", "End of work"), text: $model.draft.schedule.offWorkTime)
                Toggle(t("半小时提醒", "Half-hour reminders"), isOn: $model.draft.schedule.halfHourReminders)
                Toggle(t("午饭提醒", "Lunch reminder"), isOn: $model.draft.schedule.lunchReminder)
                Toggle(t("下班提醒", "End-of-work reminder"), isOn: $model.draft.schedule.offWorkReminder)
            }
            SettingsCard {
                Toggle(t("工作日首次打开问候", "First-launch workday greeting"), isOn: $model.draft.greetings.workday.enabled)
                HStack { TextField("07:00", text: $model.draft.greetings.workday.start); Text("—"); TextField("11:00", text: $model.draft.greetings.workday.end) }
                Toggle(t("休息日首次打开问候", "First-launch day-off greeting"), isOn: $model.draft.greetings.dayOff.enabled)
                HStack { TextField("07:00", text: $model.draft.greetings.dayOff.start); Text("—"); TextField("18:00", text: $model.draft.greetings.dayOff.end) }
                Toggle(t("安静时段", "Quiet hours"), isOn: $model.draft.quietHours.enabled)
                HStack { TextField("22:30", text: $model.draft.quietHours.start); Text("—"); TextField("08:30", text: $model.draft.quietHours.end) }
            }
        }
    }

    private var languageSection: some View {
        SettingsPage(title: t("台词", "Dialogue"), subtitle: t("选择语言包与偶尔出现的台词。", "Choose a dialogue pack and occasional chatter.")) {
            SettingsCard {
                Picker(t("界面语言", "Interface language"), selection: $model.draft.ui.locale) {
                    Text("简体中文").tag("zh-CN"); Text("English").tag("en")
                }
                Picker(t("语言包", "Dialogue pack"), selection: $model.draft.language.packId) {
                    ForEach(model.compatibleLanguages) { Text($0.manifest.displayName).tag($0.id) }
                }
                Toggle(t("闲聊", "Idle chatter"), isOn: $model.draft.language.idleEnabled)
                Toggle(t("罕见台词", "Rare lines"), isOn: $model.draft.language.rareEnabled)
                Stepper(t("最短间隔：\(Int(model.draft.language.idleMinMinutes)) 分钟", "Minimum interval: \(Int(model.draft.language.idleMinMinutes)) min"), value: $model.draft.language.idleMinMinutes, in: 1...180)
                Stepper(t("最长间隔：\(Int(model.draft.language.idleMaxMinutes)) 分钟", "Maximum interval: \(Int(model.draft.language.idleMaxMinutes)) min"), value: $model.draft.language.idleMaxMinutes, in: 1...240)
            }
            SettingsCard {
                Text(t("台词类型", "Dialogue categories")).font(.headline)
                Toggle(t("作息台词", "Schedule lines"), isOn: $model.draft.language.categories.schedule)
                Toggle(t("系统状态台词", "System status lines"), isOn: $model.draft.language.categories.system)
                Toggle(t("日历台词", "Calendar lines"), isOn: $model.draft.language.categories.calendar)
                Toggle(t("任务台词", "Task lines"), isOn: $model.draft.language.categories.agents)
                Toggle(t("闹钟与计时台词", "Alarm and timer lines"), isOn: $model.draft.language.categories.clock)
            }
            SettingsCard {
                Text(t("任务提示音", "Task sounds")).font(.headline)
                Toggle(t("等待审核 / 确认时播放", "Play when review or confirmation is needed"), isOn: $model.draft.sound.needsInput.enabled)
                soundChoiceRow(selection: $model.draft.sound.needsInput.soundId)
                Divider()
                Toggle(t("任务完成时播放", "Play when a task completes"), isOn: $model.draft.sound.taskComplete.enabled)
                soundChoiceRow(selection: $model.draft.sound.taskComplete.soundId)
            }
        }
    }

    private func soundChoiceRow(selection: Binding<String>) -> some View {
        HStack {
            soundPicker(selection: selection)
            Button(t("试听", "Preview")) { model.previewSound(selection.wrappedValue) }
        }
    }

    private var connectionSection: some View {
        SettingsPage(title: t("连接与隐私", "Connections & Privacy"), subtitle: t("只读取本机状态文件；任务正文不会上传。", "Only local status files are read; task content is never uploaded.")) {
            SettingsCard {
                Toggle("Codex", isOn: $model.draft.integrations.codex)
                Toggle("Claude Code", isOn: $model.draft.integrations.claudeCode)
                Toggle(t("日历", "Calendar"), isOn: $model.draft.integrations.calendar)
                Toggle(t("显示任务标题", "Show task titles"), isOn: $model.draft.privacy.includeTaskTitles)
                Toggle(t("显示日历标题", "Show calendar titles"), isOn: $model.draft.privacy.includeCalendarTitles)
            }
            integrationCard(provider: "codex", title: "Codex")
            integrationCard(provider: "claude", title: "Claude Code")
        }
    }

    private func integrationCard(provider: String, title: String) -> some View {
        SettingsCard {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    if let status = model.integrationStatuses[provider] {
                        Label(
                            status.detail,
                            systemImage: status.verified ? "checkmark.circle.fill" : status.installed ? "exclamationmark.circle" : "xmark.circle"
                        )
                        .foregroundStyle(status.verified ? .green : status.installed ? .orange : .secondary)
                    } else {
                        Text(t("正在检查…", "Checking…")).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.integrationBusy.contains(provider) { ProgressView().controlSize(.small) }
                Button(model.integrationStatuses[provider]?.installed == true ? t("重新连接", "Reconnect") : t("一键连接", "Connect")) {
                    model.connectIntegration(provider)
                }.disabled(model.integrationBusy.contains(provider))
            }
            if provider == "codex" {
                Text(t("安装后只需在任一 Codex 任务输入 /hooks 并允许水滴鱼一次。", "After installation, enter /hooks in any Codex task and allow the pet once."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(t("安装后重新打开 Claude Code 会话即可，不需要终端窗口。", "Restart the Claude Code session after installation; no Terminal window is used."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var clocksSection: some View {
        SettingsPage(title: t("闹钟与计时器", "Alarms & Timers"), subtitle: t("到点后闹钟会震动；快速计时只在最后 15 分钟拿起闹钟。", "The clock shakes when due; quick timers hold it only during their final 15 minutes.")) {
            SettingsCard {
                Text(t("计时器", "Timer")).font(.headline)
                if let timer = model.clockState.timer {
                    Text(timer.label.isEmpty ? (model.clockService?.remainingTimerText() ?? "—") : "\(timer.label) · \(model.clockService?.remainingTimerText() ?? "—")")
                        .font(.system(.title2, design: .rounded).monospacedDigit())
                    HStack {
                        Button(timer.state == "running" ? t("暂停", "Pause") : t("继续", "Resume")) { model.pauseOrResumeTimer() }
                        Button(t("延长 5 分钟", "Add 5 minutes")) { model.extendTimer() }
                        Button(t("取消", "Cancel"), role: .destructive) { model.cancelTimer() }
                    }
                } else {
                    TextField(t("计时名称（可选）", "Timer label (optional)"), text: $model.timerLabel)
                    Stepper(t("\(model.timerMinutes) 分钟", "\(model.timerMinutes) minutes"), value: $model.timerMinutes, in: 1...(7 * 24 * 60))
                    Button(t("开始计时", "Start timer")) { model.startTimer() }
                }
            }
            SettingsCard {
                Text(t("新闹钟", "New alarm")).font(.headline)
                TextField(t("名称（可选）", "Label (optional)"), text: $model.alarmLabel)
                TextField("HH:mm", text: $model.alarmTime)
                Picker(t("重复", "Repeat"), selection: $model.alarmMode) {
                    Text(t("单次", "Once")).tag("once")
                    Text(t("每天", "Daily")).tag("daily")
                    Text(t("工作日", "Workdays")).tag("workdays")
                    Text(t("每周一至五", "Weekly Mon–Fri")).tag("weekly")
                }
                if model.alarmMode == "once" { DatePicker(t("日期", "Date"), selection: $model.alarmDate, displayedComponents: .date) }
                Button(t("添加闹钟", "Add alarm")) { model.createAlarm() }
            }
            if !model.clockState.alarms.isEmpty {
                SettingsCard {
                    Text(t("已保存的闹钟", "Saved alarms")).font(.headline)
                    ForEach(model.clockState.alarms) { alarm in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { alarm.enabled },
                                set: { model.toggleAlarm(alarm, enabled: $0) }
                            )).labelsHidden()
                            Text(alarm.time).monospacedDigit().font(.headline)
                            Text(alarm.label.isEmpty ? alarmModeName(alarm.mode) : alarm.label)
                            Spacer()
                            Button(role: .destructive) { model.deleteAlarm(alarm) } label: { Image(systemName: "trash") }
                        }
                    }
                }
            }
            SettingsCard {
                Text(t("响铃", "Sounds")).font(.headline)
                Toggle(t("闹钟声音", "Alarm sound"), isOn: $model.clockSoundDraft.alarmSound.enabled)
                soundPicker(selection: $model.clockSoundDraft.alarmSound.soundId)
                Toggle(t("计时结束声音", "Timer sound"), isOn: $model.clockSoundDraft.timerSound.enabled)
                soundPicker(selection: $model.clockSoundDraft.timerSound.soundId)
                Toggle(t("安静时段也响", "Allow during quiet hours"), isOn: $model.clockSoundDraft.allowSoundDuringQuietHours)
                Button(t("保存响铃设置", "Save sound settings")) { model.saveClockPreferences() }
                if !model.clockState.alerts.isEmpty { Button(t("停止响铃", "Stop ringing")) { model.dismissClockAlerts() } }
            }
        }
    }

    private func soundPicker(selection: Binding<String>) -> some View {
        Picker(t("声音", "Sound"), selection: selection) {
            ForEach(["Glass", "Ping", "Hero", "Submarine", "Tink", "Pop", "Purr", "Bottle", "Funk"], id: \.self) { Text($0).tag($0) }
        }
    }

    private func visualStylePicker(title: String, ids: [String], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(ids, id: \.self) { id in
                    Button {
                        selection.wrappedValue = id
                    } label: {
                        VStack(spacing: 5) {
                            if let image = accessoryPreviewImage(id: id) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                            }
                            Text(accessoryDisplayName(id: id))
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            selection.wrappedValue == id
                                ? Color.accentColor.opacity(0.14)
                                : SettingsSurfacePalette.subtleFill,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    selection.wrappedValue == id ? Color.accentColor : SettingsSurfacePalette.separator,
                                    lineWidth: selection.wrappedValue == id ? 1.5 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessoryDisplayName(id: id))
                    .accessibilityValue(selection.wrappedValue == id ? t("已选择", "Selected") : "")
                }
            }
        }
    }

    private func accessoryPreviewImage(id: String) -> NSImage? {
        guard let accessory = model.accessories.first(where: { $0.id == id }) else { return nil }
        return NSImage(contentsOf: accessory.artURL)
    }

    private func accessoryDisplayName(id: String) -> String {
        model.accessories.first(where: { $0.id == id })?.manifest.displayName ?? id
    }

    private func alarmModeName(_ mode: String) -> String {
        let names = model.isEnglish
            ? ["once": "Once", "daily": "Daily", "workdays": "Workdays", "weekly": "Weekly"]
            : ["once": "单次", "daily": "每天", "workdays": "工作日", "weekly": "每周"]
        return names[mode] ?? mode
    }

    private var performanceSection: some View {
        SettingsPage(title: t("性能与更新", "Performance & Updates"), subtitle: t("控制资源显示与内存保护。", "Control resource visibility and memory protection.")) {
            SettingsCard {
                Toggle(t("显示 CPU / 内存面板", "Show CPU / memory panel"), isOn: $model.draft.performance.panelEnabled)
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("面板位置", "Panel position")).font(.headline)
                    Picker("", selection: $model.draft.performance.panelSide) {
                        Text(t("左侧", "Left")).tag("left")
                        Text(t("右侧", "Right")).tag("right")
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 10) {
                        Text(t("下", "Bottom")).font(.caption).foregroundStyle(.secondary)
                        Slider(value: $model.draft.performance.panelVerticalPosition, in: 0...1)
                        Text(t("上", "Top")).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Text(t("贴近", "Near")).font(.caption).foregroundStyle(.secondary)
                        Slider(value: $model.draft.performance.panelDistance, in: 2...28, step: 1)
                        Text(t("远离", "Far")).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(t(
                        "浅色显示整机占用，深色显示其中水滴鱼的占用。",
                        "Light fill shows the Mac total; dark fill shows the pet within it."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .disabled(!model.draft.performance.panelEnabled)
                Toggle(t("内存持续过高时自动退出", "Quit after sustained high memory"), isOn: $model.draft.performance.autoQuitEnabled)
                Stepper(t("内存上限：\(Int(model.draft.performance.memoryLimitMb)) MB", "Memory limit: \(Int(model.draft.performance.memoryLimitMb)) MB"), value: $model.draft.performance.memoryLimitMb, in: 800...1536, step: 64)
                Toggle(t("开机自动打开", "Launch at login"), isOn: $model.draft.startup.launchAtLogin)
            }
            SettingsCard {
                Text(t("原生版分支", "Native branch")).font(.headline)
                Text("codex/native-appkit-prototype").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Text(t("当前原生版本：v\(model.updater.currentVersion) · 功能基线：Electron 1.4.5", "Native version: v\(model.updater.currentVersion) · Feature baseline: Electron 1.4.5"))
                    .foregroundStyle(.secondary)
                if !model.updateStatus.isEmpty { Text(model.updateStatus).font(.callout) }
                if let value = model.updateProgress { ProgressView(value: value) }
                HStack {
                    Button(t("检查原生版更新", "Check native updates")) { model.checkUpdate() }
                    if model.updateAvailable { Button(t("下载并安装", "Download and install")) { model.installUpdate() } }
                }
                Text(t("全程在应用内完成，不会打开终端；只接受原生渠道、匹配芯片且通过 SHA-256 与应用身份校验的安装包。", "Runs entirely in-app with no Terminal; only native-channel packages matching the Mac architecture, SHA-256 digest and app identity are accepted."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func t(_ zh: String, _ en: String) -> String { model.isEnglish ? en : zh }
}

struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 24, weight: .semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsSurfacePalette.controlBackground, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(SettingsSurfacePalette.separator))
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: SettingsViewModel
    private var refreshTimer: Timer?
    init(
        runtime: AppRuntime, clockService: ClockService?, messengerService: FishMessengerService?,
        onApply: @escaping @MainActor () -> Void
    ) {
        let viewModel = SettingsViewModel(
            runtime: runtime, clockService: clockService, messengerService: messengerService,
            onApply: onApply
        )
        self.viewModel = viewModel
        let hosting = NSHostingController(rootView: BrandedSettingsView(model: viewModel))
        let window = NSWindow(contentViewController: hosting)
        window.title = "水滴鱼"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // The pet and its scene overlay are floating panels. Keep Settings at
        // the same level so those transparent desktop panels cannot intercept
        // its controls.
        window.level = .floating
        window.setContentSize(NSSize(width: 820, height: 600))
        window.minSize = NSSize(width: 760, height: 540)
        window.center()
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true
    }

    func select(_ section: SettingsSection) { viewModel.selectedSection = section }

    func mergeQuickSettingsFromRuntime() { viewModel.mergeQuickSettingsFromRuntime() }

    override func showWindow(_ sender: Any?) {
        if window?.isVisible != true {
            window?.makeFirstResponder(nil)
            viewModel.reloadFromRuntime()
        }
        super.showWindow(sender)
        constrainWindowToVisibleScreen()
        window?.makeKeyAndOrderFront(sender)
        window?.orderFrontRegardless()
        startRefreshTimer()
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        stopRefreshTimer()
    }

    private func constrainWindowToVisibleScreen() {
        guard let window else { return }
        let screen = window.screen
            ?? NSScreen.screens.first(where: { $0.visibleFrame.intersects(window.frame) })
            ?? NSScreen.main
        guard let screen else { return }
        let insetVisibleFrame = screen.visibleFrame.insetBy(dx: 10, dy: 10)
        var frame = window.frame
        frame.size.width = min(frame.width, insetVisibleFrame.width)
        frame.size.height = min(frame.height, insetVisibleFrame.height)
        frame.origin.x = min(max(frame.minX, insetVisibleFrame.minX), insetVisibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, insetVisibleFrame.minY), insetVisibleFrame.maxY - frame.height)
        window.setFrame(frame, display: true)
    }

    private func startRefreshTimer() {
        stopRefreshTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.viewModel.refreshClock() }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
