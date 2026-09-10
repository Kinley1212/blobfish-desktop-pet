import Darwin
import Foundation

struct CalendarEasterEggRules: Decodable {
    let times: [String: String]
    let primaryTimes: [String]
    let solar: [String: String]
    let lunar: [String: String]
    let monthStart: String

    static func load() throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: ResourceLocator.packsRoot().appendingPathComponent("calendar-easter-eggs.json")))
    }

    func dateEvent(_ date: Date, calendar: Calendar) -> String? {
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = calendar.timeZone
        // Full components include the leap-month flag on macOS 13 too; requesting
        // Calendar.Component.isLeapMonth directly would require macOS 14.
        let lunarDate = chinese.dateComponents(in: calendar.timeZone, from: date)
        if lunarDate.isLeapMonth != true, let month = lunarDate.month, let day = lunarDate.day,
           let event = lunar["\(month)-\(day)"] { return event }
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return nil }
        return solar[String(format: "%02d-%02d", month, day)] ?? (day == 1 ? monthStart : nil)
    }
}

/// At most one date greeting and two ordinary time surprises daily. Named 520/1314
/// moments are exempt from the ordinary quota, but never bypass quiet/busy checks.
final class CalendarEasterEggScheduler {
    struct State: Codable {
        var version = 1
        var day = ""
        var attempted: Set<String> = []
        var dateDelivered = false
        var ordinaryCount = 0
        var lastOrdinaryAt: Double = 0
    }
    private let rules: CalendarEasterEggRules
    private let fileURL: URL?
    private let random: () -> Double
    private(set) var state = State()
    private(set) var loadError: Error?

    init(rules: CalendarEasterEggRules, fileURL: URL? = nil, random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.rules = rules; self.fileURL = fileURL; self.random = random
        guard let fileURL else { return }
        do {
            var info = stat()
            if lstat(fileURL.path, &info) != 0 {
                if errno == ENOENT { return }
                throw CocoaError(.fileReadNoPermission)
            }
            guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_mode & 0o077 == 0,
                  info.st_size <= 16 * 1024 else { throw CocoaError(.fileReadNoPermission) }
            let loaded = try JSONDecoder().decode(State.self, from: Data(contentsOf: fileURL))
            guard loaded.version == 1, loaded.attempted.count <= 12, (0...2).contains(loaded.ordinaryCount),
                  loaded.day.count <= 10 else { throw CocoaError(.fileReadCorruptFile) }
            state = loaded
        } catch { loadError = error }
    }

    @discardableResult
    func poll(at date: Date, calendar: Calendar = Calendar(identifier: .gregorian), enabled: Bool, quiet: Bool, busy: Bool,
              deliver: (String) -> Bool) throws -> String? {
        guard enabled, !quiet, !busy, loadError == nil else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let hour = parts.hour, let minute = parts.minute else { return nil }
        let dayKey = String(format: "%04d-%02d-%02d", year, month, day)
        var next = state.day == dayKey ? state : State(day: dayKey)
        let time = String(format: "%02d:%02d", hour, minute)
        if let event = rules.times[time], !next.attempted.contains(event) {
            let primary = rules.primaryTimes.contains(time)
            if primary || (next.ordinaryCount < 2 && date.timeIntervalSince1970 - next.lastOrdinaryAt >= 3600) {
                next.attempted.insert(event)
                if primary || random() < 0.25 {
                    // Save before displaying: an I/O failure must not create repeat greetings.
                    var accepted = next
                    if !primary { accepted.ordinaryCount += 1; accepted.lastOrdinaryAt = date.timeIntervalSince1970 }
                    try save(accepted)
                    if deliver(event) { return event }
                    // A busy presentation may retry within this minute, never after it.
                    next.attempted.remove(event)
                    try save(next)
                    return nil
                }
                try save(next)
            }
        }
        if !next.dateDelivered, let event = rules.dateEvent(date, calendar: calendar) {
            next.dateDelivered = true
            try save(next)
            if deliver(event) { return event }
            next.dateDelivered = false
            try save(next)
        }
        return nil
    }

    private func save(_ next: State) throws {
        if let fileURL {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(next)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }
        state = next
    }
}
