import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var draft: AppConfig
    @Published var message = ""
    @Published var selectedSection = SettingsSection.character
    @Published var clockState: ClockState
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
    @Published var fishRecords: [FishMessageRecord] = []
    @Published var fishContacts: [FishContact] = []
    @Published var fishDraftMessage = ""

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
    private let onApply: () -> Void
    private let presenceProvider: @MainActor () -> FishPresence?

    init(
        runtime: AppRuntime, clockService: ClockService?, messengerService: FishMessengerService?,
        presenceProvider: @escaping @MainActor () -> FishPresence?, onApply: @escaping () -> Void
    ) {
        self.runtime = runtime
        self.clockService = clockService
        self.messengerService = messengerService
        self.presenceProvider = presenceProvider
        integrationManager = IntegrationManager(supportDirectory: runtime.configStore.fileURL.deletingLastPathComponent())
        clockState = clockService?.state ?? .empty
        draft = runtime.config
        characters = (try? runtime.catalog?.characters()) ?? []
        languages = (try? runtime.catalog?.languages()) ?? []
        accessories = runtime.accessories
        self.onApply = onApply
        if !runtime.warnings.isEmpty { message = runtime.warnings.joined(separator: "\n") }
        refreshIntegrations()
        refreshFishFriends()
        messengerService?.addStateObserver { [weak self] in self?.refreshFishFriends() }
    }

    func refreshFishFriends() {
        fishDisplayName = messengerService?.profile?.displayName ?? ""
        fishPreferences = messengerService?.preferences ?? .defaults
        fishRecords = messengerService?.records.sorted { $0.sentAt > $1.sentAt } ?? []
        fishContacts = messengerService?.profile?.contacts ?? []
    }

    func saveFishSettings() {
        guard let messengerService else { return }
        do {
            try messengerService.updateDisplayName(fishDisplayName)
            messengerService.updatePreferences(fishPreferences)
            message = isEnglish ? "Fish friend settings saved." : "鱼友设置已保存。"
        } catch { message = String(describing: error) }
    }

    func sendFishMessage(to contact: FishContact) {
        let text = fishDraftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let messengerService else { return }
        fishDraftMessage = ""
        Task { @MainActor in
            do { try await messengerService.send(text: text, to: contact.id) }
            catch { self.message = String(describing: error) }
        }
    }

    func startVisit(_ contact: FishContact) {
        guard let messengerService, fishPreferences.visitsEnabled, let presence = presenceProvider() else { return }
        Task { @MainActor in
            do { try await messengerService.send(text: "来串门啦！", to: contact.id, kind: .visitStart, presence: presence) }
            catch { self.message = String(describing: error) }
        }
    }

    func endVisit(_ contact: FishContact) {
        guard let messengerService else { return }
        Task { @MainActor in
            do { try await messengerService.send(text: "下次再玩。", to: contact.id, kind: .visitEnd) }
            catch { self.message = String(describing: error) }
        }
    }

    func markFishMessagesRead() { messengerService?.markRead() }

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
        do { try clockService?.updatePreferences(clockState.preferences); refreshClock() }
        catch { message = String(describing: error) }
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

    private func refreshClock() { clockState = clockService?.state ?? .empty }

    var isEnglish: Bool { draft.ui.locale == "en" }

    func apply() {
        do {
            try runtime.update { $0 = draft }
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

struct BrandedSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        HStack(spacing: 0) {
            brandedSidebar
            VStack(spacing: 0) {
                if model.selectedSection == .character {
                    characterWorkspace
                } else {
                    ScrollView { section.padding(30).frame(maxWidth: 760, alignment: .leading) }
                }
                Divider()
                HStack {
                    Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Button(model.isEnglish ? "Reset" : "恢复默认") { model.reset() }
                    Button(model.isEnglish ? "Apply" : "应用") { model.apply() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(16)
                .background(Color.white.opacity(0.74))
            }
            .frame(minWidth: 650, minHeight: 620)
        }
        .frame(minWidth: 920, minHeight: 680)
        .background(
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.98, blue: 0.97), Color(red: 0.98, green: 0.97, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var brandedSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("DESKTOP PET").font(.caption.weight(.bold)).tracking(2.2).foregroundStyle(Color(red: 0.28, green: 0.48, blue: 0.47))
                Text(currentCharacter?.manifest.displayName ?? t("水滴鱼", "Blobfish"))
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text(t("陪你工作，也记得喘口气。", "A quiet companion for focused work."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 18)

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
        .padding(24)
        .frame(width: 235)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.58))
        .overlay(alignment: .trailing) { Divider() }
    }

    private func sidebarButton(_ section: SettingsSection, _ icon: String, zh: String, en: String) -> some View {
        Button {
            model.selectedSection = section
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 22)
                Text(t(zh, en)).fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .leading)
            .contentShape(Rectangle())
            .foregroundStyle(model.selectedSection == section ? Color.white : Color.primary.opacity(0.72))
            .background(
                RoundedRectangle(cornerRadius: 15)
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
            subtitle: t("端到端加密传话、双鱼串门、未读记录和个性气泡。", "Encrypted messages, visits, unread history, and custom bubbles.")
        ) {
            fishProfileCard
            fishContactsCard
            fishHistoryCard
        }
    }

    private var fishProfileCard: some View {
        SettingsCard {
                Text(t("我的鱼友资料", "My fish profile")).font(.headline)
                TextField(t("显示名字", "Display name"), text: $model.fishDisplayName)
                    .textFieldStyle(.roundedBorder)
                Picker(t("消息气泡", "Message bubble"), selection: $model.fishPreferences.bubbleColor) {
                    Text(t("海水蓝", "Ocean blue")).tag("#1F7AE8")
                    Text(t("珊瑚粉", "Coral pink")).tag("#E65D83")
                    Text(t("海草绿", "Seaweed green")).tag("#2B9C77")
                    Text(t("葡萄紫", "Grape purple")).tag("#7957C8")
                    Text(t("夜空黑", "Night black")).tag("#384052")
                }
                Toggle(t("允许好友串门", "Allow friend visits"), isOn: $model.fishPreferences.visitsEnabled)
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

    private var fishContactsCard: some View {
        SettingsCard {
                Text(t("好友与直接聊天", "Friends & direct chat")).font(.headline)
                if model.fishContacts.isEmpty {
                    Text(t("还没有配对好友，请先从右键菜单导入鱼鱼码。", "No friends yet. Import a fish code from the context menu first."))
                        .foregroundStyle(.secondary)
                }
                ForEach(model.fishContacts) { contact in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(contact.nickname ?? contact.invite.displayName).fontWeight(.semibold)
                            Spacer()
                            if model.messengerService?.activeVisitContactID == contact.id {
                                Text(t("串门中 · 已停游", "Visiting · paused")).foregroundStyle(.pink)
                                Button(t("结束串门", "End visit")) { model.endVisit(contact) }
                            } else {
                                Button(t("邀请串门", "Invite over")) { model.startVisit(contact) }
                            }
                        }
                        HStack {
                            TextField(t("输入传话内容", "Type a message"), text: $model.fishDraftMessage)
                                .textFieldStyle(.roundedBorder)
                            Button(t("发送", "Send")) { model.sendFishMessage(to: contact) }
                        }
                    }
                    Divider()
                }
        }
    }

    private var fishHistoryCard: some View {
        SettingsCard {
            fishHistoryHeader
            if model.fishRecords.isEmpty {
                Text(t("还没有传话记录。", "No messages yet.")).foregroundStyle(.secondary)
            }
            ForEach(model.fishRecords.prefix(100)) { record in
                FishHistoryRow(record: record, isEnglish: model.isEnglish)
                Divider()
            }
        }
    }

    private var fishHistoryHeader: some View {
        HStack {
            Text(t("消息记录", "Message history")).font(.headline)
            Spacer()
            if fishUnreadCount > 0 {
                Text(model.isEnglish ? "\(fishUnreadCount) unread" : "\(fishUnreadCount) 条未读")
                    .foregroundStyle(.red)
            }
            Button(t("全部标为已读", "Mark all read")) { model.markFishMessagesRead() }
        }
    }

    private var fishUnreadCount: Int {
        model.fishRecords.filter { $0.direction == .incoming && !$0.isRead }.count
    }

    private var currentCharacter: CharacterPack? {
        model.characters.first { $0.id == model.draft.pet.characterPackId }
    }

    private var characterWorkspace: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 16) {
                Text(t("角色与动作", "Character & Motion"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
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
                        customization: model.draft.pet.customization[model.draft.pet.characterPackId]
                    )
                    .frame(width: 280, height: 180)
                    Text(currentCharacter?.manifest.displayName ?? t("角色预览", "Character preview"))
                        .font(.headline)
                    Text(t("拖动滑杆会立即反映在这里", "Changes appear here immediately"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.black.opacity(0.07)))

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
                }
                .padding(16)
                .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 18))
            }
            .frame(width: 320, alignment: .topLeading)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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
        .padding(28)
    }

    private var accessoryEditors: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(["face", "hat", "eyewear", "hand"], id: \.self) { slot in
                Picker(slotName(slot), selection: accessoryBinding(slot: slot)) {
                    Text(t("不使用", "None")).tag("")
                    ForEach(model.accessories.filter { $0.manifest.slot == slot }) { accessory in
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
            Text(t("闹钟位置", "Alarm clock position")).font(.subheadline.weight(.semibold))
            accessoryTuningEditor(id: "alarm-clock")
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
                diySlider(t("身体胖瘦", "Body width"), part: "body", key: "width", range: 0.7...1.3, fallback: 1)
                diySlider(t("身体高矮", "Body height"), part: "body", key: "height", range: 0.7...1.3, fallback: 1)
                diySlider(t("手 / 鱼鳍大小", "Arm / fin size"), part: "fins", key: "size", range: 0.5...1.6, fallback: 1)
                diySlider(t("手 / 鱼鳍左右", "Arm / fin horizontal"), part: "fins", key: "offsetX", range: -16...16, fallback: 0)
                diySlider(t("手 / 鱼鳍上下", "Arm / fin vertical"), part: "fins", key: "offsetY", range: -16...16, fallback: 0)
                diySlider(t("眼睛大小", "Eye size"), part: "eyes", key: "size", range: 0.6...1.6, fallback: 1)
                diySlider(t("眼睛间距", "Eye spacing"), part: "eyes", key: "spacing", range: -12...12, fallback: 0)
                diySlider(t("眼睛上下", "Eye vertical"), part: "eyes", key: "offsetY", range: -14...14, fallback: 0)
                diySlider(t("嘴巴大小", "Mouth size"), part: "mouth", key: "size", range: 0.6...1.5, fallback: 1)
                diySlider(t("嘴巴上下", "Mouth vertical"), part: "mouth", key: "offsetY", range: -14...14, fallback: 0)
                diySlider(t("鼻子大小", "Nose size"), part: "nose", key: "size", range: 0.6...1.6, fallback: 1)
                diySlider(t("鼻子上下", "Nose vertical"), part: "nose", key: "offsetY", range: -14...14, fallback: 0)
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
                AppearanceJSON.accessorySpec(
                    in: model.draft,
                    characterID: model.draft.pet.characterPackId
                ).equipped[slot] ?? ""
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
        VStack(alignment: .leading, spacing: 6) {
            accessorySlider(t("大小", "Size"), id: id, key: "size", range: 0.4...2, fallback: 1)
            accessorySlider(t("宽度", "Width"), id: id, key: "width", range: 0.5...1.8, fallback: 1)
            accessorySlider(t("高度", "Height"), id: id, key: "height", range: 0.5...1.8, fallback: 1)
            accessorySlider(t("左右", "Horizontal"), id: id, key: "offsetX", range: -30...30, fallback: 0)
            accessorySlider(t("上下", "Vertical"), id: id, key: "offsetY", range: -30...30, fallback: 0)
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
        SettingsPage(title: t("闹钟与计时器", "Alarms & Timers"), subtitle: t("与 1.4.5 共用记录；到点后闹钟会震动。", "Shares 1.4.5 state; the clock shakes when it rings.")) {
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
                Toggle(t("闹钟声音", "Alarm sound"), isOn: $model.clockState.preferences.alarmSound.enabled)
                soundPicker(selection: $model.clockState.preferences.alarmSound.soundId)
                Toggle(t("计时结束声音", "Timer sound"), isOn: $model.clockState.preferences.timerSound.enabled)
                soundPicker(selection: $model.clockState.preferences.timerSound.soundId)
                Toggle(t("安静时段也响", "Allow during quiet hours"), isOn: $model.clockState.preferences.allowSoundDuringQuietHours)
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
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 28, weight: .bold))
            Text(subtitle).foregroundStyle(.secondary)
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.separator.opacity(0.6)))
    }
}

private struct FishHistoryRow: View {
    let record: FishMessageRecord
    let isEnglish: Bool

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: iconName)
                .foregroundStyle(record.isRead ? Color.secondary : Color.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.senderName).font(.caption.weight(.semibold))
                Text(record.text).textSelection(.enabled)
                Text(record.sentAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if record.direction == .incoming && !record.isRead {
                Text(isEnglish ? "Unread" : "未读").font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var iconName: String {
        record.direction == .incoming ? "arrow.down.left.circle.fill" : "arrow.up.right.circle"
    }
}

final class SettingsWindowController: NSWindowController {
    private let viewModel: SettingsViewModel
    init(
        runtime: AppRuntime, clockService: ClockService?, messengerService: FishMessengerService?,
        presenceProvider: @escaping @MainActor () -> FishPresence?, onApply: @escaping () -> Void
    ) {
        let viewModel = SettingsViewModel(
            runtime: runtime, clockService: clockService, messengerService: messengerService,
            presenceProvider: presenceProvider, onApply: onApply
        )
        self.viewModel = viewModel
        let hosting = NSHostingController(rootView: BrandedSettingsView(model: viewModel))
        let window = NSWindow(contentViewController: hosting)
        window.title = "水滴鱼"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1_100, height: 760))
        window.minSize = NSSize(width: 920, height: 680)
        window.center()
        super.init(window: window)
        shouldCascadeWindows = true
    }

    func select(_ section: SettingsSection) { viewModel.selectedSection = section }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
