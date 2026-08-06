import AppKit
import SwiftUI

@MainActor
final class ClockQuickViewModel: ObservableObject {
    @Published private(set) var state: ClockState
    @Published private(set) var timerText: String?
    @Published var soundDraft: ClockSoundPreferencesDraft
    @Published var timerMinutes = 25
    @Published var timerLabel = ""
    @Published var alarmLabel = ""
    @Published var alarmTime = "09:00"
    @Published var alarmMode = "daily"
    @Published var alarmDate = Date().addingTimeInterval(24 * 60 * 60)
    @Published var message = ""
    @Published private(set) var locale: String

    private let service: ClockService
    private let soundPlayer = SoundPlayer()

    init(service: ClockService, locale: String) {
        self.service = service
        self.locale = locale
        state = service.state
        timerText = service.remainingTimerText()
        soundDraft = ClockSoundPreferencesDraft(service.state.preferences)
    }

    var isEnglish: Bool { locale == "en" }

    func updateLocale(_ locale: String) {
        self.locale = locale
    }

    func reload() {
        refresh()
        soundDraft = ClockSoundPreferencesDraft(service.state.preferences)
        message = ""
    }

    func refresh() {
        state = service.state
        timerText = service.remainingTimerText()
    }

    func startTimer(minutes: Int? = nil) {
        let duration = minutes ?? timerMinutes
        perform(
            successZH: "计时已开始。", successEN: "Timer started.",
            action: { try service.startTimer(minutes: duration, label: timerLabel, source: ClockTimerSource.quick) }
        )
    }

    func pauseOrResumeTimer() {
        if state.timer?.state == "running" {
            perform(successZH: "计时已暂停。", successEN: "Timer paused.") { try service.pauseTimer() }
        } else {
            perform(successZH: "计时已继续。", successEN: "Timer resumed.") { try service.resumeTimer() }
        }
    }

    func extendTimer() {
        perform(successZH: "已延长 5 分钟。", successEN: "Added 5 minutes.") {
            try service.extendTimer(minutes: 5)
        }
    }

    func cancelTimer() {
        perform(successZH: "计时已取消。", successEN: "Timer cancelled.") { try service.cancelTimer() }
    }

    func createAlarm() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        perform(successZH: "闹钟已添加。", successEN: "Alarm added.") {
            try service.createAlarm(
                label: alarmLabel,
                mode: alarmMode,
                time: alarmTime,
                date: alarmMode == "once" ? formatter.string(from: alarmDate) : nil,
                weekdays: alarmMode == "weekly" ? [1, 2, 3, 4, 5] : []
            )
        }
    }

    func toggleAlarm(_ alarm: ClockState.Alarm, enabled: Bool) {
        perform(successZH: "闹钟已更新。", successEN: "Alarm updated.") {
            try service.setAlarmEnabled(id: alarm.id, enabled: enabled)
        }
    }

    func deleteAlarm(_ alarm: ClockState.Alarm) {
        perform(successZH: "闹钟已删除。", successEN: "Alarm deleted.") {
            try service.deleteAlarm(id: alarm.id)
        }
    }

    func snooze(_ alert: ClockState.Alert) {
        perform(successZH: "稍后 5 分钟再提醒。", successEN: "Snoozed for 5 minutes.") {
            try service.snoozeAlert(id: alert.id, minutes: 5)
        }
    }

    func dismiss(_ alert: ClockState.Alert) {
        perform(successZH: "提醒已关闭。", successEN: "Alert dismissed.") {
            try service.dismissAlert(id: alert.id)
        }
    }

    func saveSounds() {
        perform(successZH: "响铃设置已保存。", successEN: "Sound settings saved.") {
            try service.updatePreferences(soundDraft.applying(to: service.state.preferences))
        }
        soundDraft = ClockSoundPreferencesDraft(service.state.preferences)
    }

    func previewSound(_ id: String) {
        soundPlayer.play(id: id)
    }

    private func perform(successZH: String, successEN: String, action: () throws -> Void) {
        do {
            try action()
            refresh()
            message = isEnglish ? successEN : successZH
        } catch {
            refresh()
            message = (isEnglish ? "Could not update the clock: " : "没有改好：") + error.localizedDescription
        }
    }
}

struct ClockQuickView: View {
    @ObservedObject var model: ClockQuickViewModel
    @State private var showsSoundSettings = false

    private let soundIDs = ["Glass", "Ping", "Hero", "Submarine", "Tink", "Pop", "Purr", "Bottle", "Funk"]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    alertCard
                    timerCard
                    alarmCreatorCard
                    savedAlarmsCard
                    soundCard
                }
                .padding(14)
            }
            Divider()
            HStack {
                Text(model.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
            }
            .frame(minHeight: 20)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.7))
        }
        .frame(minWidth: 460, minHeight: 500)
        .background(
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.98, blue: 0.97), Color(red: 0.99, green: 0.97, blue: 0.94)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "alarm.waves.left.and.right")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color(red: 0.82, green: 0.31, blue: 0.34))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(t("闹钟与计时器", "Alarms & Timers"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(t("快速设定，不会打开完整设置。", "Set the time quickly without opening full settings."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.58))
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder private var alertCard: some View {
        if !model.state.alerts.isEmpty {
            QuickClockCard {
                Label(t("正在提醒", "Active alerts"), systemImage: "bell.badge.fill")
                    .font(.headline).foregroundStyle(.red)
                ForEach(model.state.alerts) { alert in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.label.isEmpty ? t("时间到了", "Time is up") : alert.label)
                                .fontWeight(.semibold)
                            Text(alert.sourceType == "alarm" ? t("闹钟", "Alarm") : t("计时器", "Timer"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(t("稍后 5 分钟", "Snooze 5m")) { model.snooze(alert) }
                        Button(t("知道了", "Dismiss")) { model.dismiss(alert) }
                    }
                }
            }
        }
    }

    private var timerCard: some View {
        QuickClockCard {
            Label(t("快速计时", "Quick timer"), systemImage: "timer")
                .font(.headline)
            if let timer = model.state.timer {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(timer.label.isEmpty ? t("计时中", "Timer") : timer.label)
                            .font(.callout).foregroundStyle(.secondary)
                        Text(model.timerText ?? "—")
                            .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    }
                    Spacer()
                    Text(timer.state == "running" ? t("进行中", "Running") : t("已暂停", "Paused"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                HStack {
                    Button(timer.state == "running" ? t("暂停", "Pause") : t("继续", "Resume")) {
                        model.pauseOrResumeTimer()
                    }
                    Button(t("延长 5 分钟", "Add 5m")) { model.extendTimer() }
                    Spacer()
                    Button(t("取消", "Cancel"), role: .destructive) { model.cancelTimer() }
                }
            } else {
                HStack(spacing: 7) {
                    ForEach([5, 15, 25, 45], id: \.self) { minutes in
                        Button(minutes == 25 ? t("25 分钟专注", "25m focus") : t("\(minutes) 分钟", "\(minutes)m")) {
                            model.startTimer(minutes: minutes)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                TextField(t("计时名称（可选）", "Timer label (optional)"), text: $model.timerLabel)
                HStack {
                    Stepper(t("\(model.timerMinutes) 分钟", "\(model.timerMinutes) minutes"), value: $model.timerMinutes, in: 1...(7 * 24 * 60))
                    Spacer()
                    Button(t("开始", "Start")) { model.startTimer() }
                        .buttonStyle(.borderedProminent)
                }
                Text(t("快速计时只会在最后 15 分钟让水滴鱼拿起闹钟。", "The pet holds the clock only during the final 15 minutes of a quick timer."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var alarmCreatorCard: some View {
        QuickClockCard {
            Label(t("添加闹钟", "Add alarm"), systemImage: "alarm")
                .font(.headline)
            HStack {
                TextField(t("名称（可选）", "Label (optional)"), text: $model.alarmLabel)
                TextField("HH:mm", text: $model.alarmTime)
                    .frame(width: 72)
                    .multilineTextAlignment(.center)
                    .font(.body.monospacedDigit())
            }
            HStack {
                Picker(t("重复", "Repeat"), selection: $model.alarmMode) {
                    Text(t("单次", "Once")).tag("once")
                    Text(t("每天", "Daily")).tag("daily")
                    Text(t("工作日", "Workdays")).tag("workdays")
                    Text(t("每周一至五", "Mon–Fri weekly")).tag("weekly")
                }
                if model.alarmMode == "once" {
                    DatePicker("", selection: $model.alarmDate, displayedComponents: .date)
                        .labelsHidden()
                }
                Spacer()
                Button(t("添加", "Add")) { model.createAlarm() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder private var savedAlarmsCard: some View {
        if !model.state.alarms.isEmpty {
            QuickClockCard {
                Label(t("已保存的闹钟", "Saved alarms"), systemImage: "list.bullet")
                    .font(.headline)
                ForEach(model.state.alarms) { alarm in
                    HStack(spacing: 9) {
                        Toggle("", isOn: Binding(
                            get: { alarm.enabled },
                            set: { model.toggleAlarm(alarm, enabled: $0) }
                        )).labelsHidden()
                        Text(alarm.time).monospacedDigit().fontWeight(.semibold)
                        Text(alarm.label.isEmpty ? alarmModeName(alarm.mode) : alarm.label)
                            .lineLimit(1)
                        Spacer()
                        Button(role: .destructive) { model.deleteAlarm(alarm) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var soundCard: some View {
        QuickClockCard {
            DisclosureGroup(isExpanded: $showsSoundSettings) {
                VStack(alignment: .leading, spacing: 10) {
                    soundRow(
                        title: t("闹钟声音", "Alarm sound"),
                        enabled: $model.soundDraft.alarmSound.enabled,
                        soundID: $model.soundDraft.alarmSound.soundId
                    )
                    Divider()
                    soundRow(
                        title: t("计时结束声音", "Timer sound"),
                        enabled: $model.soundDraft.timerSound.enabled,
                        soundID: $model.soundDraft.timerSound.soundId
                    )
                    Toggle(t("安静时段也响", "Allow during quiet hours"), isOn: $model.soundDraft.allowSoundDuringQuietHours)
                    HStack {
                        Spacer()
                        Button(t("保存响铃设置", "Save sounds")) { model.saveSounds() }
                    }
                }
                .padding(.top, 10)
            } label: {
                Label(t("响铃设置", "Sound settings"), systemImage: "speaker.wave.2")
                    .font(.headline)
            }
        }
    }

    private func soundRow(title: String, enabled: Binding<Bool>, soundID: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: enabled)
            HStack {
                Picker(t("声音", "Sound"), selection: soundID) {
                    ForEach(soundIDs, id: \.self) { Text($0).tag($0) }
                }
                Button(t("试听", "Preview")) { model.previewSound(soundID.wrappedValue) }
            }
            .disabled(!enabled.wrappedValue)
        }
    }

    private func alarmModeName(_ mode: String) -> String {
        let names = model.isEnglish
            ? ["once": "Once", "daily": "Daily", "workdays": "Workdays", "weekly": "Weekly"]
            : ["once": "单次", "daily": "每天", "workdays": "工作日", "weekly": "每周"]
        return names[mode] ?? mode
    }

    private func t(_ zh: String, _ en: String) -> String { model.isEnglish ? en : zh }
}

private struct QuickClockCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.07)))
    }
}

@MainActor
final class ClockQuickWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: ClockQuickViewModel
    private var refreshTimer: Timer?

    init(service: ClockService, locale: String) {
        let viewModel = ClockQuickViewModel(service: service, locale: locale)
        self.viewModel = viewModel
        let hosting = NSHostingController(rootView: ClockQuickView(model: viewModel))
        let window = NSWindow(contentViewController: hosting)
        window.title = locale == "en" ? "Alarms & Timers" : "闹钟与计时器"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 520, height: 640))
        window.minSize = NSSize(width: 460, height: 500)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true
    }

    func updateLocale(_ locale: String) {
        viewModel.updateLocale(locale)
        window?.title = locale == "en" ? "Alarms & Timers" : "闹钟与计时器"
    }

    override func showWindow(_ sender: Any?) {
        viewModel.reload()
        super.showWindow(sender)
        startRefreshTimer()
    }

    func windowWillClose(_ notification: Notification) {
        stopRefreshTimer()
    }

    private func startRefreshTimer() {
        stopRefreshTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.viewModel.refresh()
        }
        if let refreshTimer { RunLoop.main.add(refreshTimer, forMode: .common) }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
