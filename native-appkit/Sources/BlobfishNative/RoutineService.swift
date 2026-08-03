import AppKit
import Darwin
import Foundation

final class RoutineService {
    var onPhrase: ((String, [String: JSONValue]) -> Void)?
    var hasActiveTasks = false

    private let runtime: AppRuntime
    private let supportDirectory: URL
    private var timer: Timer?
    private var nextIdleAt = Date.distantFuture
    private var deliveredReminderKeys = Set<String>()
    private var notifiedBatteryThresholds = Set<Int>()
    private var lockedAt: Date?
    private let batteryQueue = DispatchQueue(label: "com.blobfish.native.battery", qos: .utility)

    init(runtime: AppRuntime) {
        self.runtime = runtime
        supportDirectory = runtime.configStore.fileURL.deletingLastPathComponent()
    }

    func start() {
        deliverStartupGreetingIfNeeded()
        scheduleNextIdle()
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer!, forMode: .common)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil
        )
    }

    func stop() {
        timer?.invalidate(); timer = nil
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func poll() {
        let now = Date()
        if !isQuiet(now), let reminder = scheduleReminder(at: now) {
            onPhrase?(reminder.0, reminder.1)
        }
        if runtime.config.language.idleEnabled, !hasActiveTasks, !isQuiet(now), now >= nextIdleAt {
            onPhrase?("idle.chatter", dateContext(now))
            scheduleNextIdle()
        }
        readBattery()
    }

    private func scheduleReminder(at date: Date) -> (String, [String: JSONValue])? {
        let schedule = runtime.config.schedule
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        guard schedule.workdays.contains(weekday) else { return nil }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        let current = hour * 60 + minute
        let lunch = Self.minutes(schedule.lunchTime)
        let offWork = Self.minutes(schedule.offWorkTime)
        let event: String?
        var context: [String: JSONValue] = [:]
        if schedule.lunchReminder, current == lunch - 5 { event = "schedule.lunchSoon" }
        else if schedule.offWorkReminder, current == offWork - 5 { event = "schedule.offWorkSoon"; context["farewell"] = .string("下次见") }
        else if schedule.offWorkReminder, current == offWork - 30 { event = "schedule.offWorkHalfHour" }
        else if schedule.halfHourReminders, minute == 0 || minute == 30 { event = "schedule.halfHour" }
        else { event = nil }
        guard let event else { return nil }
        let key = "\(components.year!)-\(components.month!)-\(components.day!)-\(hour)-\(minute)-\(event)"
        guard deliveredReminderKeys.insert(key).inserted else { return nil }
        if deliveredReminderKeys.count > 256 { deliveredReminderKeys.removeAll(keepingCapacity: true) }
        return (event, context)
    }

    private func deliverStartupGreetingIfNeeded() {
        let now = Date()
        guard !isQuiet(now) else { return }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let dateKey = formatter.string(from: now)
        let file = supportDirectory.appendingPathComponent("startup-greeting-state.json")
        var info = stat()
        let safeState = lstat(file.path, &info) == 0
            && info.st_mode & S_IFMT == S_IFREG
            && info.st_uid == getuid()
            && info.st_mode & 0o077 == 0
            && info.st_size >= 0 && info.st_size <= 16 * 1024
        if safeState, let data = try? Data(contentsOf: file),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["version"] as? Int == 1, object["lastGreetingDate"] as? String == dateKey { return }
        let weekday = Calendar.current.component(.weekday, from: now) - 1
        let isWorkday = runtime.config.schedule.workdays.contains(weekday)
        let range = isWorkday ? runtime.config.greetings.workday : runtime.config.greetings.dayOff
        let current = Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)
        guard range.enabled, current >= Self.minutes(range.start), current < Self.minutes(range.end) else { return }
        onPhrase?(isWorkday ? "startup.workdayMorning" : "startup.dayOff", dateContext(now))
        let object: [String: Any] = ["version": 1, "lastGreetingDate": dateKey]
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? data.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    private func scheduleNextIdle() {
        let language = runtime.config.language
        let seconds = Double.random(in: language.idleMinMinutes...language.idleMaxMinutes) * 60
        nextIdleAt = Date().addingTimeInterval(seconds)
    }

    private func isQuiet(_ date: Date) -> Bool {
        let quiet = runtime.config.quietHours
        guard quiet.enabled else { return false }
        let current = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
        let start = Self.minutes(quiet.start), end = Self.minutes(quiet.end)
        if start == end { return true }
        return start < end ? current >= start && current < end : current >= start || current < end
    }

    private func readBattery() {
        batteryQueue.async { [weak self] in
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); process.arguments = ["-g", "batt"]
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe()
            do {
                try process.run(); process.waitUntilExit()
                guard process.terminationStatus == 0,
                      let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else { return }
                guard text.lowercased().contains("battery power") else {
                    DispatchQueue.main.async { self?.notifiedBatteryThresholds.removeAll() }
                    return
                }
                guard
                      let match = text.range(of: #"\b\d{1,3}%"#, options: .regularExpression),
                      let percentage = Int(text[match].dropLast()) else { return }
                DispatchQueue.main.async { self?.handleBattery(percentage) }
            } catch { return }
        }
    }

    private func handleBattery(_ percentage: Int) {
        let crossed = [20, 10, 5, 3, 2].filter { percentage <= $0 && !notifiedBatteryThresholds.contains($0) }
        guard let selected = crossed.min() else { return }
        crossed.forEach { notifiedBatteryThresholds.insert($0) }
        onPhrase?("system.battery", ["battery": .number(Double(selected))])
    }

    @objc private func screenLocked() { lockedAt = Date() }

    @objc private func screenUnlocked() {
        let seconds = lockedAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
        lockedAt = nil
        onPhrase?("system.unlocked", ["lockedSeconds": .number(Double(seconds))])
    }

    private func dateContext(_ date: Date) -> [String: JSONValue] {
        [
            "hour": .number(Double(Calendar.current.component(.hour, from: date))),
            "minute": .number(Double(Calendar.current.component(.minute, from: date))),
            "weekday": .number(Double(Calendar.current.component(.weekday, from: date) - 1)),
        ]
    }

    private static func minutes(_ value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : 0
    }
}
