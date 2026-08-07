import Darwin
import Foundation

enum FishMessageKind: String, Codable {
    case text
    case visitStart
    case visitAccept
    case visitEnd
    case status
    case receipt
    case interaction
}

enum FishDeliveryState: String, Codable, Equatable, Hashable {
    case sending
    case relayed
    case delivered
    case read
    case failed
}

enum FishDeliveryReceiptState: String, Codable, Equatable {
    case delivered
    case read
}

enum FishDeliveryStatePolicy {
    static func relayed(after current: FishDeliveryState?) -> FishDeliveryState {
        switch current {
        case .delivered, .read:
            return current ?? .relayed
        case .sending, .relayed, .failed, nil:
            return .relayed
        }
    }

    static func applying(
        _ receipt: FishDeliveryReceiptState,
        to current: FishDeliveryState
    ) -> FishDeliveryState {
        let incoming: FishDeliveryState = receipt == .read ? .read : .delivered
        let rank: [FishDeliveryState: Int] = [
            .sending: 0, .failed: 0, .relayed: 1, .delivered: 2, .read: 3,
        ]
        return rank[incoming, default: 0] > rank[current, default: 0] ? incoming : current
    }
}

struct FishDeliveryReceipt: Codable, Equatable {
    let messageID: UUID
    let state: FishDeliveryReceiptState
}

enum FishRemoteInteraction: String, Codable, CaseIterable, Identifiable {
    case pet
    case hug
    case highFive

    var id: String { rawValue }

    func title(isEnglish: Bool) -> String {
        switch self {
        case .pet: return isEnglish ? "Pet" : "摸摸頭"
        case .hug: return isEnglish ? "Hug" : "抱抱"
        case .highFive: return isEnglish ? "High five" : "擊掌"
        }
    }

    var symbolName: String {
        switch self {
        case .pet: return "hand.point.up.left.fill"
        case .hug: return "heart.fill"
        case .highFive: return "hands.clap.fill"
        }
    }

    var phraseEvent: String { "messenger.remote.\(rawValue)" }
}

enum FishUserStatus: String, Codable, CaseIterable, Identifiable {
    case fishing, working, doNotDisturb, resting, happy, unhappy
    var id: String { rawValue }
    func title(isEnglish: Bool) -> String {
        switch self {
        case .fishing: return isEnglish ? "Slacking" : "摸魚"
        case .working: return isEnglish ? "Working" : "工作"
        case .doNotDisturb: return isEnglish ? "Do Not Disturb" : "勿擾"
        case .resting: return isEnglish ? "Resting" : "休息"
        case .happy: return isEnglish ? "Happy" : "開心"
        case .unhappy: return isEnglish ? "Unhappy" : "不開心"
        }
    }
    var emoji: String {
        switch self {
        case .fishing: return "🐟"
        case .working: return "💼"
        case .doNotDisturb: return "🌙"
        case .resting: return "☕️"
        case .happy: return "😊"
        case .unhappy: return "🌧️"
        }
    }
    var faceID: String {
        switch self {
        case .fishing: return "face-smug"
        case .working: return "face-determined"
        case .doNotDisturb: return "face-sleepy"
        case .resting: return "face-relieved"
        case .happy: return "face-happy"
        case .unhappy: return "face-pitiful"
        }
    }
}

struct FishPresence: Codable, Equatable {
    let characterPackID: String
    let customization: JSONValue?
    let accessories: JSONValue?
    let status: FishUserStatus?
    let statusFaceID: String?
    let statusAccessoryID: String?
    let statusAccessories: JSONValue?

    init(
        characterPackID: String, customization: JSONValue?, accessories: JSONValue?,
        status: FishUserStatus? = nil, statusFaceID: String? = nil,
        statusAccessoryID: String? = nil, statusAccessories: JSONValue? = nil
    ) {
        self.characterPackID = characterPackID
        self.customization = customization
        self.accessories = accessories
        self.status = status
        self.statusFaceID = statusFaceID
        self.statusAccessoryID = statusAccessoryID
        self.statusAccessories = statusAccessories
    }
}

struct FishMessageRecord: Codable, Equatable, Identifiable {
    enum Direction: String, Codable { case incoming, outgoing }

    let id: UUID
    let contactID: UUID
    let direction: Direction
    let sentAt: Date
    let senderName: String
    let text: String
    let kind: FishMessageKind
    var isRead: Bool
    let bubbleColor: String?
    let presence: FishPresence?
    var deliveryState: FishDeliveryState? = nil
    var interaction: FishRemoteInteraction? = nil

    var effectiveDeliveryState: FishDeliveryState? {
        guard direction == .outgoing else { return nil }
        return deliveryState ?? .relayed
    }
}

struct FishFriendPreferences: Codable, Equatable {
    var bubbleColor: String
    var incomingSoundEnabled: Bool
    var incomingSoundID: String
    var visitsEnabled: Bool
    var messageDisplaySeconds: Double? = nil
    var messageIndicatorID: String? = nil
    var currentStatus: FishUserStatus? = nil
    var statusFaceIDs: [String: String]? = nil
    var statusAccessoryIDs: [String: String]? = nil
    var deliveryPresentation: String? = nil
    var statusCustomizations: [String: JSONValue]? = nil
    var statusAccessorySpecs: [String: JSONValue]? = nil
    var messageShowsMailbox: Bool? = nil
    var messageShowsBubble: Bool? = nil
    var visitShowsMailbox: Bool? = nil
    var visitShowsBubble: Bool? = nil

    var effectiveMessageShowsMailbox: Bool { messageShowsMailbox ?? !showsIncomingBubble }
    var effectiveMessageShowsBubble: Bool { messageShowsBubble ?? showsIncomingBubble }
    var effectiveVisitShowsMailbox: Bool { visitShowsMailbox ?? false }
    var effectiveVisitShowsBubble: Bool { visitShowsBubble ?? true }

    func customization(for status: FishUserStatus, fallback: JSONValue?) -> JSONValue? {
        statusCustomizations?[status.rawValue] ?? fallback
    }

    var showsIncomingBubble: Bool { deliveryPresentation == "bubble" }

    func faceID(for status: FishUserStatus) -> String {
        statusFaceIDs?[status.rawValue] ?? status.faceID
    }

    func accessoryID(for status: FishUserStatus) -> String? {
        statusAccessoryIDs?[status.rawValue].flatMap { $0.isEmpty ? nil : $0 }
    }

    var effectiveMessageDisplaySeconds: TimeInterval {
        min(120, max(1, messageDisplaySeconds ?? 20))
    }

    var effectiveMessageIndicatorID: String {
        FishMessageIndicatorStyle.normalized(messageIndicatorID)
    }

    static let defaults = FishFriendPreferences(
        bubbleColor: "#1F7AE8",
        incomingSoundEnabled: true,
        incomingSoundID: "Submarine",
        visitsEnabled: true,
        messageDisplaySeconds: 20,
        messageIndicatorID: FishMessageIndicatorStyle.defaultID
    )
}

enum FishMessageIndicatorStyle {
    static let defaultID = "message-mailbox"
    static let ids = [defaultID, "message-envelope", "message-flying-letter", "message-sea-mail"]

    static func normalized(_ value: String?) -> String {
        guard let value, ids.contains(value) else { return defaultID }
        return value
    }
}

enum FishMessageHistory {
    static let maximumRecords = 500

    static func bounded(_ records: [FishMessageRecord]) -> [FishMessageRecord] {
        Array(records.suffix(maximumRecords))
    }

    static func append(_ record: FishMessageRecord, to records: inout [FishMessageRecord]) {
        records.append(record)
        let overflow = records.count - maximumRecords
        if overflow > 0 { records.removeFirst(overflow) }
    }
}

enum FishVisitPolicy {
    static func canActivate(contact: FishContact, preferences: FishFriendPreferences) -> Bool {
        preferences.visitsEnabled && !contact.blocked && !contact.muted
    }

    static func activeContactID(
        after kind: FishMessageKind,
        from contact: FishContact,
        current: UUID?,
        preferences: FishFriendPreferences
    ) -> UUID? {
        switch kind {
        case .visitStart, .visitAccept:
            return canActivate(contact: contact, preferences: preferences) ? contact.id : current
        case .visitEnd:
            return current == contact.id ? nil : current
        case .text, .status, .receipt, .interaction:
            return current
        }
    }

    static func shouldPresent(
        kind: FishMessageKind,
        from contact: FishContact,
        preferences: FishFriendPreferences
    ) -> Bool {
        guard !contact.blocked, !contact.muted else { return false }
        switch kind {
        case .text, .status, .interaction:
            return true
        case .visitStart, .visitAccept, .visitEnd:
            return preferences.visitsEnabled
        case .receipt:
            return false
        }
    }
}

final class FishFriendStore {
    enum StoreError: Error, LocalizedError {
        case invalidStateFile

        var errorDescription: String? {
            "Fish message history is not a private, valid state file."
        }
    }

    private static let maximumFileBytes = 2 * 1024 * 1024
    private let fileURL: URL

    init(directoryURL: URL) {
        fileURL = directoryURL.appendingPathComponent("fish-friends.json")
    }

    func load() throws -> (FishFriendPreferences, [FishMessageRecord]) {
        struct State: Codable { let preferences: FishFriendPreferences; let records: [FishMessageRecord] }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return (.defaults, []) }
        var info = stat()
        guard lstat(fileURL.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(),
              info.st_mode & 0o077 == 0,
              info.st_size >= 0,
              info.st_size <= Self.maximumFileBytes else {
            throw StoreError.invalidStateFile
        }
        let data = try Data(contentsOf: fileURL)
        guard data.count <= Self.maximumFileBytes,
              let state = try? JSONDecoder().decode(State.self, from: data) else {
            throw StoreError.invalidStateFile
        }
        return (state.preferences, FishMessageHistory.bounded(state.records))
    }

    func save(preferences: FishFriendPreferences, records: [FishMessageRecord]) throws {
        struct State: Codable { let preferences: FishFriendPreferences; let records: [FishMessageRecord] }
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
                  info.st_uid == getuid(),
                  info.st_mode & 0o077 == 0 else {
                throw StoreError.invalidStateFile
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(State(preferences: preferences, records: FishMessageHistory.bounded(records)))
            .write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
