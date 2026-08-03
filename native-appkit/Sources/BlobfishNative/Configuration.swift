import Darwin
import Foundation

struct AppConfig: Codable, Equatable {
    struct UI: Codable, Equatable { var locale: String }
    struct Schedule: Codable, Equatable {
        var workdays: [Int]
        var lunchTime: String
        var offWorkTime: String
        var halfHourReminders: Bool
        var lunchReminder: Bool
        var offWorkReminder: Bool
    }
    struct GreetingWindow: Codable, Equatable { var enabled: Bool; var start: String; var end: String }
    struct Greetings: Codable, Equatable { var workday: GreetingWindow; var dayOff: GreetingWindow }
    struct QuietHours: Codable, Equatable { var enabled: Bool; var start: String; var end: String }
    struct LanguageCategories: Codable, Equatable {
        var schedule: Bool; var system: Bool; var calendar: Bool; var agents: Bool; var clock: Bool
    }
    struct Language: Codable, Equatable {
        var packId: String
        var idleEnabled: Bool
        var rareEnabled: Bool
        var idleMinMinutes: Double
        var idleMaxMinutes: Double
        var categories: LanguageCategories
    }
    struct Pet: Codable, Equatable {
        var characterPackId: String
        var speed: Double
        var scale: Double
        var roamWhenTasks: Bool
        var roamWhenNoTasks: Bool
        var moveAxis: String
        var customization: [String: JSONValue]
        var accessories: [String: JSONValue]
    }
    struct Startup: Codable, Equatable { var launchAtLogin: Bool }
    struct Performance: Codable, Equatable {
        var panelEnabled: Bool
        var autoQuitEnabled: Bool
        var memoryLimitMb: Double
        var panelSide: String
        var panelVerticalPosition: Double
    }
    struct Integrations: Codable, Equatable { var calendar: Bool; var codex: Bool; var claudeCode: Bool }
    struct Privacy: Codable, Equatable { var includeTaskTitles: Bool; var includeCalendarTitles: Bool }
    struct SoundChoice: Codable, Equatable { var enabled: Bool; var soundId: String }
    struct Sound: Codable, Equatable { var taskComplete: SoundChoice; var needsInput: SoundChoice }

    var version: Int
    var ui: UI
    var schedule: Schedule
    var greetings: Greetings
    var quietHours: QuietHours
    var language: Language
    var pet: Pet
    var startup: Startup
    var performance: Performance
    var integrations: Integrations
    var privacy: Privacy
    var sound: Sound

    static let defaults = AppConfig(
        version: 1,
        ui: UI(locale: "zh-CN"),
        schedule: Schedule(
            workdays: [1, 2, 3, 4, 5], lunchTime: "13:00", offWorkTime: "19:00",
            halfHourReminders: true, lunchReminder: true, offWorkReminder: true
        ),
        greetings: Greetings(
            workday: GreetingWindow(enabled: true, start: "07:00", end: "11:00"),
            dayOff: GreetingWindow(enabled: true, start: "07:00", end: "18:00")
        ),
        quietHours: QuietHours(enabled: false, start: "22:30", end: "08:30"),
        language: Language(
            packId: "blobfish-zh-TW", idleEnabled: true, rareEnabled: true,
            idleMinMinutes: 12, idleMaxMinutes: 35,
            categories: LanguageCategories(schedule: true, system: true, calendar: true, agents: true, clock: true)
        ),
        pet: Pet(
            characterPackId: "blobfish", speed: 1.5, scale: 1,
            roamWhenTasks: true, roamWhenNoTasks: false, moveAxis: "horizontal",
            customization: [:], accessories: [:]
        ),
        startup: Startup(launchAtLogin: false),
        performance: Performance(
            panelEnabled: false,
            autoQuitEnabled: false,
            memoryLimitMb: 1024,
            panelSide: "left",
            panelVerticalPosition: 0.5
        ),
        integrations: Integrations(calendar: false, codex: true, claudeCode: true),
        privacy: Privacy(includeTaskTitles: false, includeCalendarTitles: true),
        sound: Sound(
            taskComplete: SoundChoice(enabled: true, soundId: "Glass"),
            needsInput: SoundChoice(enabled: true, soundId: "Ping")
        )
    )

    func validated() throws -> AppConfig {
        var normalized = self
        guard version == 1 else { throw ConfigError.invalid("unsupported version") }
        normalized.ui.locale = ui.locale == "en" ? "en" : "zh-CN"
        guard schedule.workdays.count <= 7,
              schedule.workdays.allSatisfy({ (0...6).contains($0) }) else {
            throw ConfigError.invalid("workdays")
        }
        normalized.schedule.workdays = Array(Set(schedule.workdays)).sorted()
        for (label, value) in [
            ("lunch time", schedule.lunchTime), ("off-work time", schedule.offWorkTime),
            ("workday greeting start", greetings.workday.start), ("workday greeting end", greetings.workday.end),
            ("day-off greeting start", greetings.dayOff.start), ("day-off greeting end", greetings.dayOff.end),
            ("quiet start", quietHours.start), ("quiet end", quietHours.end),
        ] where !Self.isTime(value) {
            throw ConfigError.invalid(label)
        }
        guard Self.minutes(greetings.workday.start) < Self.minutes(greetings.workday.end),
              Self.minutes(greetings.dayOff.start) < Self.minutes(greetings.dayOff.end) else {
            throw ConfigError.invalid("greeting range")
        }
        guard Self.isPackId(language.packId), Self.isPackId(pet.characterPackId) else {
            throw ConfigError.invalid("pack id")
        }
        guard (1...180).contains(language.idleMinMinutes),
              (1...240).contains(language.idleMaxMinutes),
              language.idleMinMinutes <= language.idleMaxMinutes else {
            throw ConfigError.invalid("idle interval")
        }
        guard (0.25...4).contains(pet.speed), (0.65...1.5).contains(pet.scale),
              pet.moveAxis == "horizontal" || pet.moveAxis == "vertical" else {
            throw ConfigError.invalid("pet movement")
        }
        guard (800...1536).contains(performance.memoryLimitMb) else {
            throw ConfigError.invalid("memory limit")
        }
        guard performance.panelSide == "left" || performance.panelSide == "right",
              (0...1).contains(performance.panelVerticalPosition) else {
            throw ConfigError.invalid("performance panel position")
        }
        for id in [sound.taskComplete.soundId, sound.needsInput.soundId] {
            guard !id.isEmpty, id.utf8.count <= 64,
                  id.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
                throw ConfigError.invalid("sound id")
            }
        }
        let validSounds = Set(["Glass", "Ping", "Hero", "Submarine", "Tink", "Pop", "Purr", "Bottle", "Funk"])
        if !validSounds.contains(normalized.sound.taskComplete.soundId) {
            normalized.sound.taskComplete.soundId = Self.defaults.sound.taskComplete.soundId
        }
        if !validSounds.contains(normalized.sound.needsInput.soundId) {
            normalized.sound.needsInput.soundId = Self.defaults.sound.needsInput.soundId
        }
        return normalized
    }

    private static func isPackId(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$"#, options: .regularExpression) != nil
    }

    private static func isTime(_ value: String) -> Bool {
        value.range(of: #"^(?:[01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil
    }

    private static func minutes(_ value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
    }
}

enum ConfigError: Error { case invalid(String); case unsafeFile }

struct ConfigLoadResult {
    let config: AppConfig
    let warning: String?
}

final class NativeConfigStore {
    static let maximumBytes = 1024 * 1024
    let fileURL: URL

    init(directoryURL: URL) {
        fileURL = directoryURL.appendingPathComponent("settings.json")
    }

    func load() -> ConfigLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ConfigLoadResult(config: .defaults, warning: nil)
        }
        do {
            var info = stat()
            guard lstat(fileURL.path, &info) == 0,
                  info.st_mode & S_IFMT == S_IFREG,
                  info.st_uid == getuid(),
                  info.st_size >= 0,
                  info.st_size <= Self.maximumBytes else { throw ConfigError.unsafeFile }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            let defaults = try decoder.decode(JSONValue.self, from: encoder.encode(AppConfig.defaults))
            let user = try decoder.decode(JSONValue.self, from: Data(contentsOf: fileURL, options: .mappedIfSafe))
            let merged = JSONValue.merging(defaults: defaults, user: user)
            let config = try decoder.decode(AppConfig.self, from: encoder.encode(merged)).validated()
            return ConfigLoadResult(config: config, warning: nil)
        } catch {
            return ConfigLoadResult(config: .defaults, warning: "设置文件无效，原生版暂时使用默认值：\(error)")
        }
    }

    func save(_ config: AppConfig) throws {
        let validated = try config.validated()
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if FileManager.default.fileExists(atPath: fileURL.path) {
            var info = stat()
            guard lstat(fileURL.path, &info) == 0,
                  info.st_mode & S_IFMT == S_IFREG,
                  info.st_uid == getuid() else { throw ConfigError.unsafeFile }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(validated)
        data.append(0x0A)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
