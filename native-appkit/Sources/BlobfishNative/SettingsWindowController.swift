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

    let runtime: AppRuntime
    let characters: [CharacterPack]
    let languages: [LanguagePack]
    let accessories: [AccessoryPack]
    let clockService: ClockService?
    let integrationManager: IntegrationManager
    private let onApply: () -> Void

    init(runtime: AppRuntime, clockService: ClockService?, onApply: @escaping () -> Void) {
        self.runtime = runtime
        self.clockService = clockService
        integrationManager = IntegrationManager(supportDirectory: runtime.configStore.fileURL.deletingLastPathComponent())
        clockState = clockService?.state ?? .empty
        draft = runtime.config
        characters = (try? runtime.catalog?.characters()) ?? []
        languages = (try? runtime.catalog?.languages()) ?? []
        accessories = runtime.accessories
        self.onApply = onApply
        if !runtime.warnings.isEmpty { message = runtime.warnings.joined(separator: "\n") }
        refreshIntegrations()
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
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case character, schedule, language, connection, clocks, performance
    var id: String { rawValue }
}

struct NativeSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        NavigationView {
            List(selection: $model.selectedSection) {
                sidebar(.character, "person.crop.circle", zh: "角色与动作", en: "Character & Motion")
                sidebar(.schedule, "clock", zh: "问候与作息", en: "Schedule & Greetings")
                sidebar(.language, "quote.bubble", zh: "台词", en: "Dialogue")
                sidebar(.connection, "link", zh: "连接与隐私", en: "Connections & Privacy")
                sidebar(.clocks, "timer", zh: "闹钟与计时器", en: "Alarms & Timers")
                sidebar(.performance, "gauge.with.dots.needle.33percent", zh: "性能与更新", en: "Performance & Updates")
            }
            .listStyle(.sidebar)
            .frame(minWidth: 210)

            VStack(spacing: 0) {
                ScrollView { section.padding(30).frame(maxWidth: 760, alignment: .leading) }
                Divider()
                HStack {
                    Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Button(model.isEnglish ? "Reset" : "恢复默认") { model.reset() }
                    Button(model.isEnglish ? "Apply" : "应用") { model.apply() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(16)
            }
            .frame(minWidth: 650, minHeight: 620)
        }
        .frame(width: 920, height: 680)
    }

    @ViewBuilder private var section: some View {
        switch model.selectedSection {
        case .character: characterSection
        case .schedule: scheduleSection
        case .language: languageSection
        case .connection: connectionSection
        case .clocks: clocksSection
        case .performance: performanceSection
        }
    }

    private var characterSection: some View {
        SettingsPage(title: t("角色与动作", "Character & Motion"), subtitle: t("选择形象并决定它什么时候、怎样移动。", "Choose the character and when it should move.")) {
            SettingsCard {
                Picker(t("角色", "Character"), selection: $model.draft.pet.characterPackId) {
                    ForEach(model.characters) { Text($0.manifest.displayName).tag($0.id) }
                }
                LabeledContent(t("大小", "Size")) {
                    Slider(value: $model.draft.pet.scale, in: 0.65...1.5, step: 0.05)
                    Text(model.draft.pet.scale.formatted(.number.precision(.fractionLength(2)))).monospacedDigit()
                }
                LabeledContent(t("游动速度", "Movement speed")) {
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
            SettingsCard {
                Text(t("捏鱼 / 捏草与饰品", "Character editor & accessories")).font(.headline)
                diyEditor
            }
            SettingsCard {
                Text(t("饰品", "Accessories")).font(.headline)
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
                    ForEach(model.languages) { Text($0.manifest.displayName).tag($0.id) }
                }
                Toggle(t("闲聊", "Idle chatter"), isOn: $model.draft.language.idleEnabled)
                Toggle(t("罕见台词", "Rare lines"), isOn: $model.draft.language.rareEnabled)
                Stepper(t("最短间隔：\(Int(model.draft.language.idleMinMinutes)) 分钟", "Minimum interval: \(Int(model.draft.language.idleMinMinutes)) min"), value: $model.draft.language.idleMinMinutes, in: 1...180)
                Stepper(t("最长间隔：\(Int(model.draft.language.idleMaxMinutes)) 分钟", "Maximum interval: \(Int(model.draft.language.idleMaxMinutes)) min"), value: $model.draft.language.idleMaxMinutes, in: 1...240)
            }
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
                Toggle(t("内存持续过高时自动退出", "Quit after sustained high memory"), isOn: $model.draft.performance.autoQuitEnabled)
                Stepper(t("内存上限：\(Int(model.draft.performance.memoryLimitMb)) MB", "Memory limit: \(Int(model.draft.performance.memoryLimitMb)) MB"), value: $model.draft.performance.memoryLimitMb, in: 800...1536, step: 64)
                Toggle(t("开机自动打开", "Launch at login"), isOn: $model.draft.startup.launchAtLogin)
            }
            SettingsCard {
                Text(t("原生版分支", "Native branch")).font(.headline)
                Text("codex/native-appkit-prototype").font(.system(.body, design: .monospaced)).textSelection(.enabled)
            }
        }
    }

    private func sidebar(_ section: SettingsSection, _ icon: String, zh: String, en: String) -> some View {
        Label(t(zh, en), systemImage: icon).tag(section)
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

final class SettingsWindowController: NSWindowController {
    init(runtime: AppRuntime, clockService: ClockService?, onApply: @escaping () -> Void) {
        let viewModel = SettingsViewModel(runtime: runtime, clockService: clockService, onApply: onApply)
        let hosting = NSHostingController(rootView: NativeSettingsView(model: viewModel))
        let window = NSWindow(contentViewController: hosting)
        window.title = "水滴鱼"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 920, height: 680))
        window.center()
        super.init(window: window)
        shouldCascadeWindows = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
