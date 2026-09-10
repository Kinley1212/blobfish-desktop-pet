import Foundation

extension SelfCheck {
    static func calendarEasterEggPolicy() throws -> Bool {
        let rules = try CalendarEasterEggRules.load()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value + ":00+08:00")! }
        let scheduler = CalendarEasterEggScheduler(rules: rules, random: { 0 })
        func poll(_ value: String, enabled: Bool = true, quiet: Bool = false, busy: Bool = false) throws -> String? {
            try scheduler.poll(at: date(value), calendar: calendar, enabled: enabled, quiet: quiet, busy: busy) { _ in true }
        }
        guard try poll("2026-09-10T13:14", enabled: false) == nil,
              try poll("2026-09-10T13:14", quiet: true) == nil,
              try poll("2026-09-10T13:14", busy: true) == nil,
              try poll("2026-09-10T13:14") == "rare.time1314",
              try poll("2026-09-10T13:14") == nil,
              try poll("2026-09-10T13:15") == nil,
              try poll("2026-09-11T08:08") == "rare.time0808",
              try poll("2026-09-11T09:09") == "rare.time0909",
              try poll("2026-09-11T11:11") == nil,
              try poll("2026-09-11T17:20") == "rare.time1720" else { return false }
        for (day, event) in [("2026-02-17", "rare.dateLunarNewYear"), ("2026-03-03", "rare.dateLantern"), ("2026-09-25", "rare.dateMidAutumn"), ("2028-02-29", "rare.dateLeapDay"), ("2026-12-25", "rare.dateChristmas")] {
            guard rules.dateEvent(date(day + "T12:00"), calendar: calendar) == event else { return false }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let saved = CalendarEasterEggScheduler(rules: rules, fileURL: file)
        guard try saved.poll(at: date("2026-12-25T10:15"), calendar: calendar, enabled: true, quiet: false, busy: false, deliver: { _ in true }) == "rare.dateChristmas" else { return false }
        let reopened = CalendarEasterEggScheduler(rules: rules, fileURL: file)
        return try reopened.poll(at: date("2026-12-25T10:16"), calendar: calendar, enabled: true, quiet: false, busy: false, deliver: { _ in true }) == nil
    }
}
