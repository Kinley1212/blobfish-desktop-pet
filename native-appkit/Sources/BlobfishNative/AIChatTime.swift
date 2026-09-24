import Foundation

// Preserve the sender's timezone, including historical DST rules. Legacy data
// keeps nil timestamps; neither file modification time nor load time is evidence.
struct AIChatTimestamp: Codable, Equatable {
    let date: Date
    let timeZoneID: String

    init(date: Date = Date(), timeZone: TimeZone = .current) {
        self.date = date
        self.timeZoneID = timeZone.identifier
    }

    var validated: Self? {
        guard date.timeIntervalSince1970.isFinite,
              (-62135596800..<253402300800).contains(date.timeIntervalSince1970),
              timeZoneID.utf8.count <= 128, TimeZone(identifier: timeZoneID) != nil else { return nil }
        return self
    }

    var label: String {
        guard validated != nil, let zone = TimeZone(identifier: timeZoneID) else { return "unknown" }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = zone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date) + " [" + timeZoneID + "]"
    }
}
