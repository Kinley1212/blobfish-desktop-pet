import Darwin
import Foundation

struct ClockState: Codable, Equatable {
    struct Preferences: Codable, Equatable {
        var alarmSound: AppConfig.SoundChoice
        var timerSound: AppConfig.SoundChoice
        var allowSoundDuringQuietHours: Bool
        var defaultSnoozeMinutes: Int
    }
    struct Alarm: Codable, Equatable, Identifiable {
        var id: String; var label: String; var enabled: Bool; var mode: String; var time: String
        var date: String?; var weekdays: [Int]; var lastOccurrenceKey: String?; var createdAtMs: Double
    }
    struct TimerState: Codable, Equatable, Identifiable {
        var id: String; var label: String; var durationMs: Double; var state: String
        var createdAtMs: Double; var dueAtMs: Double?; var remainingMs: Double?
        var source: String? = nil
    }
    struct Alert: Codable, Equatable, Identifiable {
        var id: String; var sourceType: String; var sourceId: String; var label: String
        var originalDueAtMs: Double; var dueAtMs: Double; var state: String; var ringStartedAtMs: Double?
    }

    var version: Int
    var preferences: Preferences
    var alarms: [Alarm]
    var timer: TimerState?
    var alerts: [Alert]
    var lastReconciledAtMs: Double

    static let empty = ClockState(
        version: 1,
        preferences: Preferences(
            alarmSound: .init(enabled: true, soundId: "Ping"),
            timerSound: .init(enabled: true, soundId: "Glass"),
            allowSoundDuringQuietHours: true,
            defaultSnoozeMinutes: 5
        ),
        alarms: [], timer: nil, alerts: [], lastReconciledAtMs: 0
    )
}

enum ClockEvent { case alarmDue(ClockState.Alert); case timerDue(ClockState.Alert); case changed(String) }
enum ClockError: Error { case invalid(String); case unsafeFile }

enum ClockTimerSource {
    static let quick = "quick"
    static let settings = "settings"
}

enum ClockAccessoryPolicy {
    static let quickTimerThresholdMs: Double = 15 * 60 * 1_000

    static func shouldShowClock(state: ClockState, nowMs: Double) -> Bool {
        if state.alarms.contains(where: \.enabled) { return true }
        if state.alerts.contains(where: { $0.state == "ringing" || $0.state == "snoozed" }) { return true }
        guard let timer = state.timer, timer.source == ClockTimerSource.quick else { return false }
        return remainingMs(for: timer, nowMs: nowMs) <= quickTimerThresholdMs
    }

    static func remainingMs(for timer: ClockState.TimerState, nowMs: Double) -> Double {
        if timer.state == "running" {
            return max(0, (timer.dueAtMs ?? nowMs) - nowMs)
        }
        return max(0, timer.remainingMs ?? 0)
    }
}

final class ClockService {
    var onEvent: ((ClockEvent, ClockState) -> Void)?
    var onTick: ((ClockState, String?) -> Void)?
    private(set) var state: ClockState
    var workdays = [1, 2, 3, 4, 5]

    private let fileURL: URL
    private var timer: Timer?
    private var lastPollMs: Double

    init(directoryURL: URL) {
        fileURL = directoryURL.appendingPathComponent("clock-state.json")
        state = Self.load(fileURL: fileURL) ?? .empty
        lastPollMs = max(state.lastReconciledAtMs, Date().timeIntervalSince1970 * 1_000 - 10 * 60 * 1_000)
    }

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() { timer?.invalidate(); timer = nil }

    func createAlarm(label: String, mode: String, time: String, date: String?, weekdays: [Int]) throws {
        guard state.alarms.count < 50 else { throw ClockError.invalid("最多只能保存 50 个闹钟") }
        guard ["once", "daily", "workdays", "weekly"].contains(mode), Self.validTime(time) else {
            throw ClockError.invalid("闹钟时间无效")
        }
        if mode == "once", !Self.validDate(date) { throw ClockError.invalid("单次闹钟日期无效") }
        if mode == "weekly", weekdays.isEmpty { throw ClockError.invalid("每周闹钟至少选择一天") }
        let now = Date().timeIntervalSince1970 * 1_000
        state.alarms.append(.init(
            id: UUID().uuidString.lowercased(), label: Self.cleanLabel(label), enabled: true,
            mode: mode, time: time, date: mode == "once" ? date : nil,
            weekdays: mode == "weekly" ? Array(Set(weekdays)).sorted() : [],
            lastOccurrenceKey: nil, createdAtMs: now
        ))
        try persist(reason: "alarm-created")
    }

    func setAlarmEnabled(id: String, enabled: Bool) throws {
        guard let index = state.alarms.firstIndex(where: { $0.id == id }) else { return }
        state.alarms[index].enabled = enabled
        try persist(reason: "alarm-updated")
    }

    func deleteAlarm(id: String) throws {
        state.alarms.removeAll { $0.id == id }
        try persist(reason: "alarm-deleted")
    }

    func startTimer(minutes: Int, label: String, source: String = ClockTimerSource.settings) throws {
        guard state.timer == nil else { throw ClockError.invalid("已经有一个计时器在运行") }
        guard (1...(7 * 24 * 60)).contains(minutes) else { throw ClockError.invalid("计时时长无效") }
        guard source == ClockTimerSource.settings || source == ClockTimerSource.quick else {
            throw ClockError.invalid("计时来源无效")
        }
        let now = Date().timeIntervalSince1970 * 1_000
        let duration = Double(minutes * 60 * 1_000)
        state.timer = .init(
            id: UUID().uuidString.lowercased(), label: Self.cleanLabel(label), durationMs: duration,
            state: "running", createdAtMs: now, dueAtMs: now + duration, remainingMs: nil,
            source: source
        )
        try persist(reason: "timer-started")
    }

    func pauseTimer() throws {
        guard var value = state.timer, value.state == "running", let due = value.dueAtMs else { return }
        value.state = "paused"; value.remainingMs = max(0, due - Date().timeIntervalSince1970 * 1_000); value.dueAtMs = nil
        state.timer = value; try persist(reason: "timer-paused")
    }

    func resumeTimer() throws {
        guard var value = state.timer, value.state == "paused", let remaining = value.remainingMs else { return }
        value.state = "running"; value.dueAtMs = Date().timeIntervalSince1970 * 1_000 + remaining; value.remainingMs = nil
        state.timer = value; try persist(reason: "timer-resumed")
    }

    func extendTimer(minutes: Int = 5) throws {
        guard var value = state.timer else { return }
        let extra = Double(max(1, minutes) * 60 * 1_000)
        value.durationMs += extra
        if value.state == "running" { value.dueAtMs = (value.dueAtMs ?? 0) + extra }
        else { value.remainingMs = (value.remainingMs ?? 0) + extra }
        state.timer = value; try persist(reason: "timer-extended")
    }

    func cancelTimer() throws { state.timer = nil; try persist(reason: "timer-cancelled") }

    func snoozeAlert(id: String, minutes: Int = 5) throws {
        guard (1...24 * 60).contains(minutes),
              let index = state.alerts.firstIndex(where: { $0.id == id }) else { return }
        state.alerts[index].state = "snoozed"
        state.alerts[index].dueAtMs = Date().timeIntervalSince1970 * 1_000 + Double(minutes * 60 * 1_000)
        state.alerts[index].ringStartedAtMs = nil
        try persist(reason: "alert-snoozed")
    }

    func dismissAlert(id: String) throws {
        state.alerts.removeAll { $0.id == id }
        try persist(reason: "alert-dismissed")
    }

    func dismissAlerts() throws { state.alerts.removeAll(); try persist(reason: "alerts-dismissed") }

    func updatePreferences(_ preferences: ClockState.Preferences) throws {
        state.preferences = preferences
        try persist(reason: "preferences-updated")
    }

    func remainingTimerText(nowMs: Double = Date().timeIntervalSince1970 * 1_000) -> String? {
        guard let timer = state.timer else { return nil }
        let remaining = timer.state == "running" ? max(0, (timer.dueAtMs ?? nowMs) - nowMs) : max(0, timer.remainingMs ?? 0)
        let seconds = Int(ceil(remaining / 1_000))
        let hours = seconds / 3_600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, (seconds % 3_600) / 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func poll() {
        let now = Date().timeIntervalSince1970 * 1_000
        var dueEvents: [ClockEvent] = []
        for index in state.alerts.indices
        where state.alerts[index].state == "snoozed" && state.alerts[index].dueAtMs <= now {
            state.alerts[index].state = "ringing"
            state.alerts[index].ringStartedAtMs = now
            let alert = state.alerts[index]
            dueEvents.append(alert.sourceType == "alarm" ? .alarmDue(alert) : .timerDue(alert))
        }
        if let running = state.timer, running.state == "running", let due = running.dueAtMs, due <= now {
            let alert = makeAlert(sourceType: "timer", sourceID: running.id, label: running.label, dueAtMs: due, nowMs: now)
            state.timer = nil; state.alerts.append(alert); dueEvents.append(.timerDue(alert))
        }
        let calendar = Calendar.current
        for index in state.alarms.indices where state.alarms[index].enabled {
            guard let due = dueDate(for: state.alarms[index], near: Date(timeIntervalSince1970: now / 1_000)) else { continue }
            let dueMs = due.timeIntervalSince1970 * 1_000
            guard dueMs > lastPollMs, dueMs <= now, now - dueMs <= 10 * 60 * 1_000 else { continue }
            let day = calendar.dateComponents([.year, .month, .day], from: due)
            let key = "\(state.alarms[index].id):\(day.year!)-\(String(format: "%02d", day.month!))-\(String(format: "%02d", day.day!)):\(state.alarms[index].time.replacingOccurrences(of: ":", with: ""))"
            guard state.alarms[index].lastOccurrenceKey != key else { continue }
            state.alarms[index].lastOccurrenceKey = key
            if state.alarms[index].mode == "once" { state.alarms[index].enabled = false }
            let alarm = state.alarms[index]
            let alert = makeAlert(sourceType: "alarm", sourceID: alarm.id, label: alarm.label, dueAtMs: dueMs, nowMs: now)
            state.alerts.append(alert); dueEvents.append(.alarmDue(alert))
        }
        lastPollMs = now; state.lastReconciledAtMs = now
        if !dueEvents.isEmpty {
            try? save()
            for event in dueEvents { onEvent?(event, state) }
        }
        onTick?(state, remainingTimerText(nowMs: now))
    }

    private func dueDate(for alarm: ClockState.Alarm, near date: Date) -> Date? {
        let time = alarm.time.split(separator: ":").compactMap { Int($0) }
        guard time.count == 2 else { return nil }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = time[0]; components.minute = time[1]; components.second = 0
        guard let candidate = Calendar.current.date(from: components) else { return nil }
        let weekday = Calendar.current.component(.weekday, from: candidate) - 1
        switch alarm.mode {
        case "once":
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: candidate) == alarm.date ? candidate : nil
        case "daily": return candidate
        case "workdays": return workdays.contains(weekday) ? candidate : nil
        case "weekly": return alarm.weekdays.contains(weekday) ? candidate : nil
        default: return nil
        }
    }

    private func makeAlert(sourceType: String, sourceID: String, label: String, dueAtMs: Double, nowMs: Double) -> ClockState.Alert {
        .init(
            id: "alert:\(UUID().uuidString.lowercased())", sourceType: sourceType, sourceId: sourceID,
            label: label, originalDueAtMs: dueAtMs, dueAtMs: dueAtMs, state: "ringing", ringStartedAtMs: nowMs
        )
    }

    private func persist(reason: String) throws { try save(); onEvent?(.changed(reason), state) }

    private func save() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(state); data.append(0x0A)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func load(fileURL: URL) -> ClockState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        var info = stat()
        guard lstat(fileURL.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              info.st_size >= 0, info.st_size <= 1024 * 1024 else { return nil }
        return try? JSONDecoder().decode(ClockState.self, from: Data(contentsOf: fileURL))
    }

    private static func validTime(_ value: String) -> Bool {
        value.range(of: #"^(?:[01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil
    }

    private static func validDate(_ value: String?) -> Bool {
        guard let value else { return false }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter.date(from: value) != nil
    }

    private static func cleanLabel(_ value: String) -> String {
        String(value.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined().prefix(60))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
