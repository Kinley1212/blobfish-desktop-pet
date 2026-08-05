import Darwin
import Foundation

enum FishMessageKind: String, Codable {
    case text
    case visitStart
    case visitAccept
    case visitEnd
}

struct FishPresence: Codable, Equatable {
    let characterPackID: String
    let customization: JSONValue?
    let accessories: JSONValue?
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
}

struct FishFriendPreferences: Codable, Equatable {
    var bubbleColor: String
    var incomingSoundEnabled: Bool
    var incomingSoundID: String
    var visitsEnabled: Bool
    var messageDisplaySeconds: Double? = nil
    var messageIndicatorID: String? = nil

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
        case .text:
            return current
        }
    }

    static func shouldPresent(
        kind: FishMessageKind,
        from contact: FishContact,
        preferences: FishFriendPreferences
    ) -> Bool {
        guard !contact.blocked, !contact.muted else { return false }
        return kind == .text || preferences.visitsEnabled
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
