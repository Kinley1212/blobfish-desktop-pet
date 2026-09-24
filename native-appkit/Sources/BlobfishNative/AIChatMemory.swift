import Darwin
import Foundation

struct AIChatMemoryState: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let characterID: String
        let languageID: String
        let user: String
        let fish: String
        var userTime: AIChatTimestamp? = nil
        var fishTime: AIChatTimestamp? = nil
    }
    struct Fact: Codable, Identifiable, Equatable {
        let id: UUID
        let text: String
        var savedAt: AIChatTimestamp? = nil
        var spokenAt: AIChatTimestamp? = nil

        // Readable context, not the numeric Date encoding used for local storage.
        var context: Context { .init(text: text, savedAt: savedAt?.label ?? "unknown", originalMessageAt: spokenAt?.label ?? "unknown") }
        struct Context: Encodable {
            let text: String
            let savedAt: String
            let originalMessageAt: String
        }
    }
    var entries: [Entry] = []
    var facts: [Fact] = []
}

final class AIChatMemoryStore {
    static let entryCountLimit = 150 // 300 individual messages
    static let factCountLimit = 100
    static let historyLimit = 1024 * 1024
    static let factsLimit = 96 * 1024
    static let totalDiskLimit = 3 * 1024 * 1024
    // One file plus one fixed atomic-write scratch file; both count toward 3 MB.
    static let fileLimit = totalDiskLimit / 2
    let fileURL: URL
    private(set) var state = AIChatMemoryState()
    private(set) var revision = UUID()
    private(set) var loadFailed = false

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("ai-chat-memory.json")
        do {
            if try safeExistingFile() {
                let data = try Data(contentsOf: fileURL)
                state = try JSONDecoder().decode(AIChatMemoryState.self, from: data)
                state = bounded(state)
            }
        } catch { loadFailed = true }
    }

    @discardableResult private func safeExistingFile() throws -> Bool {
        var info = stat()
        if lstat(fileURL.path, &info) != 0 {
            if errno == ENOENT { return false }
            throw ConfigError.unsafeFile
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_size >= 0, info.st_size <= Self.fileLimit else { throw ConfigError.unsafeFile }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return true
    }

    static func clipped(_ text: String, bytes: Int) -> String {
        var result = ""
        var count = 0
        for char in text {
            let size = String(char).utf8.count
            guard count + size <= bytes else { break }
            result.append(char); count += size
        }
        return result
    }

    private func bounded(_ source: AIChatMemoryState) -> AIChatMemoryState {
        var value = source
        value.entries = Array(value.entries.suffix(Self.entryCountLimit)).map {
            .init(characterID: Self.clipped($0.characterID, bytes: 128), languageID: Self.clipped($0.languageID, bytes: 128),
                  user: Self.clipped($0.user, bytes: 4096), fish: Self.clipped($0.fish, bytes: 2048),
                  userTime: $0.userTime?.validated, fishTime: $0.fishTime?.validated)
        }
        while !value.entries.isEmpty && encodedSize(value.entries) > Self.historyLimit { value.entries.removeFirst() }
        value.facts = Array(value.facts.suffix(Self.factCountLimit)).map { .init(id: $0.id, text: Self.clipped($0.text, bytes: 512), savedAt: $0.savedAt?.validated, spokenAt: $0.spokenAt?.validated) }
        while !value.facts.isEmpty && encodedSize(value.facts) > Self.factsLimit { value.facts.removeFirst() }
        return value
    }

    private func encodedSize<T: Encodable>(_ value: T) -> Int { (try? JSONEncoder().encode(value).count) ?? Int.max }

    private func save(_ next: AIChatMemoryState) throws {
        // Do not replace unreadable/corrupt user data silently.
        guard !loadFailed else { throw ConfigError.unsafeFile }
        let next = bounded(next)
        let data = try JSONEncoder().encode(next)
        guard data.count <= Self.fileLimit else { throw ConfigError.unsafeFile }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        _ = try safeExistingFile()
        // A private scratch file prevents the atomic writer from inheriting a permissive umask.
        let scratch = directory.appendingPathComponent(".ai-chat-memory.tmp")
        let fd = open(scratch.path, O_WRONLY | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw ConfigError.unsafeFile }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_nlink == 1, info.st_size <= Self.fileLimit else {
            close(fd); throw ConfigError.unsafeFile
        }
        guard fchmod(fd, 0o600) == 0, ftruncate(fd, 0) == 0 else { close(fd); throw ConfigError.unsafeFile }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: scratch) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        guard rename(scratch.path, fileURL.path) == 0 else { throw ConfigError.unsafeFile }
        state = next
        revision = UUID()
    }

    func history(characterID: String, languageID: String) -> [AIChatMessage] {
        state.entries.filter { $0.characterID == characterID && $0.languageID == languageID }.suffix(6).flatMap {
            [AIChatMessage(role: "user", content: $0.user, occurredAt: $0.userTime), AIChatMessage(role: "assistant", content: $0.fish, occurredAt: $0.fishTime)]
        }
    }

    func record(user: String, fish: String, characterID: String, languageID: String, userTime: AIChatTimestamp = .init(), fishTime: AIChatTimestamp = .init()) throws {
        var next = state
        next.entries.append(.init(characterID: characterID, languageID: languageID, user: user, fish: fish, userTime: userTime, fishTime: fishTime))
        try save(next)
    }

    func remember(_ text: String, spokenAt: AIChatTimestamp? = nil, savedAt: AIChatTimestamp = .init()) throws {
        let text = Self.clipped(text.trimmingCharacters(in: .whitespacesAndNewlines), bytes: 512)
        guard !text.isEmpty, !state.facts.contains(where: { $0.text == text }) else { return }
        var next = state
        next.facts.append(.init(id: UUID(), text: text, savedAt: savedAt, spokenAt: spokenAt))
        try save(next)
    }

    func forget(_ id: UUID) throws {
        var next = state; next.facts.removeAll { $0.id == id }
        // Remove historical copies as well, so a deleted fact cannot be recalled via old turns.
        next.entries.removeAll()
        try save(next)
    }

    func clear() throws { try save(AIChatMemoryState()) }
    var bytesUsed: Int { encodedSize(state) }
}
