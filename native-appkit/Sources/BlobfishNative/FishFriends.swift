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

    static let defaults = FishFriendPreferences(
        bubbleColor: "#1F7AE8",
        incomingSoundEnabled: true,
        incomingSoundID: "Submarine",
        visitsEnabled: true
    )
}

final class FishFriendStore {
    private let fileURL: URL
    private let maximumRecords = 500

    init(directoryURL: URL) {
        fileURL = directoryURL.appendingPathComponent("fish-friends.json")
    }

    func load() -> (FishFriendPreferences, [FishMessageRecord]) {
        struct State: Codable { let preferences: FishFriendPreferences; let records: [FishMessageRecord] }
        guard let data = try? Data(contentsOf: fileURL), data.count <= 2 * 1024 * 1024,
              let state = try? JSONDecoder().decode(State.self, from: data) else {
            return (.defaults, [])
        }
        return (state.preferences, Array(state.records.suffix(maximumRecords)))
    }

    func save(preferences: FishFriendPreferences, records: [FishMessageRecord]) throws {
        struct State: Codable { let preferences: FishFriendPreferences; let records: [FishMessageRecord] }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(State(preferences: preferences, records: Array(records.suffix(maximumRecords))))
            .write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

