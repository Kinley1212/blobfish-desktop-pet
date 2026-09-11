import Foundation
import CoreFoundation
import Darwin

// A projection of the actual app-server stream, never of PermissionRequest hooks.
// This file is also compiled into the optional transparent CLI observer.
struct CodexQuestion: Codable, Equatable, Identifiable {
    struct Option: Codable, Equatable { let label: String; let description: String }
    let id: String
    let title: String
    let options: [Option]
}

struct CodexQuestionRequest: Codable, Equatable, Identifiable {
    let id: String
    let threadID: String
    let turnID: String
    let blocking: Bool
    let questions: [CodexQuestion]
}

struct CodexObservedThread: Codable, Equatable {
    let id: String
    var turnID: String
    var state: String
    var timestamp: Double
    var approvals: Set<String> = []
    var blockingQuestions: Set<String> = []
    var questions: [CodexQuestionRequest] = []
}

struct CodexObservationSnapshot: Codable, Equatable {
    var version = 1
    var timestamp: Double
    var threads: [CodexObservedThread]
}

struct CodexObservationReducer {
    private(set) var threads: [String: CodexObservedThread] = [:]
    static let maxThreads = 64
    static let observedMethods: Set<String> = [
        "turn/started", "turn/completed", "thread/closed", "thread/archived", "thread/deleted",
        "serverRequest/resolved", "item/commandExecution/requestApproval", "item/fileChange/requestApproval",
        "item/permissions/requestApproval", "mcpServer/elicitation/request", "item/tool/requestUserInput"
    ]

    static func identifier(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty, value.utf8.count <= 256,
              value.range(of: #"^[A-Za-z0-9._:@+\-]+$"#, options: .regularExpression) != nil else { return nil }
        return value
    }

    private static func requestID(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty, string.utf8.count <= 256 { return "s:" + string }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return "n:" + number.stringValue }
        return nil
    }

    static func text(_ value: Any?, limit: Int) -> String? {
        guard let value = value as? String, !value.isEmpty, value.utf8.count <= limit,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\t" }) else { return nil }
        return value
    }

    mutating func removeQuestionText() {
        for id in threads.keys { threads[id]?.questions = [] }
    }

    mutating func receive(_ message: [String: Any], now: Double, includeQuestions: Bool) {
        guard let method = message["method"] as? String, let params = message["params"] as? [String: Any] else { return }
        let threadObject = params["thread"] as? [String: Any]
        guard let threadID = Self.identifier(params["threadId"] ?? threadObject?["id"]) else { return }
        let turn = params["turn"] as? [String: Any]
        let turnID = Self.identifier(params["turnId"] ?? turn?["id"])

        if method == "turn/started", let turnID {
            if threads[threadID]?.turnID != turnID {
                threads[threadID] = CodexObservedThread(id: threadID, turnID: turnID, state: "running", timestamp: now)
            }
        } else if method == "thread/closed" || method == "thread/archived" || method == "thread/deleted" {
            threads.removeValue(forKey: threadID)
        } else if var thread = threads[threadID] {
            let previous = thread
            // A delayed response from an older turn must never clear a new question.
            if let turnID, turnID != thread.turnID { return }
            switch method {
            case "turn/completed":
                let status = turn?["status"] as? String
                thread.state = status == "failed" ? "failed" : status == "interrupted" ? "interrupted" : "ended"
                thread.approvals = []; thread.blockingQuestions = []; thread.questions = []
            case "serverRequest/resolved":
                guard let id = Self.requestID(params["requestId"]) else { return }
                thread.approvals.remove(id); thread.blockingQuestions.remove(id)
                thread.questions.removeAll { $0.id == id }
            case "item/commandExecution/requestApproval", "item/fileChange/requestApproval", "item/permissions/requestApproval", "mcpServer/elicitation/request":
                guard thread.state == "running", let id = Self.requestID(message["id"]), thread.approvals.count < 32 else { return }
                thread.approvals.insert(id)
            case "item/tool/requestUserInput":
                guard thread.state == "running", let id = Self.requestID(message["id"]),
                      let raw = params["questions"] as? [[String: Any]], !raw.isEmpty else { return }
                // Older versions' explicit auto-resolution timeout is not a blocking request.
                let blocking = params["isBlocking"] as? Bool ?? (params["autoResolutionMs"] as? NSNumber == nil)
                if blocking {
                    guard thread.blockingQuestions.contains(id) || thread.blockingQuestions.count < 32 else { return }
                    thread.blockingQuestions.insert(id)
                } else { thread.blockingQuestions.remove(id) }
                thread.questions.removeAll { $0.id == id }
                // Preview limits must not discard the authoritative waiting state.
                if includeQuestions, raw.count <= 12, thread.questions.count < 16 {
                    var questions: [CodexQuestion] = []
                    for (index, question) in raw.enumerated() {
                        // Never put a secret question on the desktop or in an observation file.
                        guard question["isSecret"] as? Bool != true,
                              let title = Self.text(question["question"], limit: 8192) else { continue }
                        let options = question["options"] as? [[String: Any]] ?? []
                        guard options.count <= 12 else { continue }
                        let safeOptions = options.compactMap { option -> CodexQuestion.Option? in
                            guard let label = Self.text(option["label"], limit: 1024) else { return nil }
                            let description = option["description"] as? String ?? ""
                            guard description.isEmpty || Self.text(description, limit: 4096) != nil else { return nil }
                            return .init(label: label, description: description)
                        }
                        guard safeOptions.count == options.count else { continue }
                        questions.append(.init(id: String(index), title: title, options: safeOptions))
                    }
                    if !questions.isEmpty {
                        thread.questions.append(.init(id: id, threadID: threadID, turnID: thread.turnID, blocking: blocking, questions: questions))
                    }
                }
            default:
                // In particular, autoApprovalReview is NOT a human approval request.
                return
            }
            // Duplicate resolved/completed events must not restart completion
            // celebrations, reorder task cards, or generate another disk write.
            guard thread != previous else { return }
            thread.timestamp = now
            threads[threadID] = thread
        }
        if !includeQuestions { removeQuestionText() }
        threads = threads.filter { $0.value.state == "running" || now - $0.value.timestamp < 60_000 }
        if threads.count > Self.maxThreads {
            for key in threads.values.sorted(by: { $0.timestamp < $1.timestamp }).prefix(threads.count - Self.maxThreads).map(\.id) {
                threads.removeValue(forKey: key)
            }
        }
        // Question previews are optional; never let them consume unbounded memory
        // or crowd authoritative approval state out of the projection file.
        var remainingTextBytes = 64 * 1024
        for id in threads.values.sorted(by: { $0.timestamp > $1.timestamp }).map(\.id) {
            let candidates = threads[id]?.questions ?? []
            let kept = candidates.filter { request in
                let size = request.questions.reduce(0) { count, question in
                    count + question.title.utf8.count + question.options.reduce(0) { $0 + $1.label.utf8.count + $1.description.utf8.count }
                }
                guard size <= remainingTextBytes else { return false }
                remainingTextBytes -= size
                return true
            }
            threads[id]?.questions = kept
        }
    }

    func snapshot(now: Double) -> CodexObservationSnapshot {
        .init(timestamp: now, threads: threads.values.sorted { $0.id < $1.id })
    }
}

enum CodexObservationFiles {
    static let maximumBytes = 512 * 1024
    static var support: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BlobfishDesktopPet") }
    static var directory: URL { support.appendingPathComponent("codex-observations") }

    static func read(_ url: URL, limit: Int = maximumBytes) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }; defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              info.st_size >= 0, info.st_size <= limit else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        return try? handle.read(upToCount: limit + 1)
    }

    static func questionsEnabled(settings: URL = support.appendingPathComponent("settings.json")) -> Bool {
        guard let data = read(settings), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let integrations = object["integrations"] as? [String: Any] else { return false }
        return integrations["codex"] as? Bool == true && integrations["codexQuestions"] as? Bool == true
    }

    static func secureDirectory(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return info.st_mode & S_IFMT == S_IFDIR && info.st_uid == getuid() && info.st_mode & 0o077 == 0
    }

    static func write(_ data: Data, to url: URL) -> Bool {
        guard data.count <= maximumBytes, secureDirectory(url.deletingLastPathComponent()) else { return false }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd); unlink(temporary.path) }
        let written = data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return data.isEmpty }
            var offset = 0
            while offset < buffer.count {
                let result = Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
                if result < 0 && errno == EINTR { continue }
                guard result > 0 else { return false }; offset += result
            }
            return true
        }
        return written && rename(temporary.path, url.path) == 0
    }

    static func load(directory: URL = directory, now: Double) -> [CodexObservedThread] {
        guard secureDirectory(directory), let entries = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }
        var urls: [URL] = []
        // Recover stale crash snapshots before applying the live-file cap. Bound
        // each scan so a crowded directory cannot monopolize the polling queue.
        for _ in 0..<1024 {
            guard let url = entries.nextObject() as? URL else { break }
            guard url.pathExtension == "json" else { continue }
            pruneExpiredProjection(url, now: now)
            if urls.count < 128, FileManager.default.fileExists(atPath: url.path) { urls.append(url) }
        }
        var newest: [String: (Double, CodexObservedThread)] = [:]
        for url in urls where url.pathExtension == "json" {
            guard let data = read(url), data.count <= maximumBytes,
                  let snapshot = try? JSONDecoder().decode(CodexObservationSnapshot.self, from: data), snapshot.version == 1,
                  snapshot.timestamp.isFinite, snapshot.timestamp <= now + 1000, now - snapshot.timestamp <= 6000,
                  snapshot.threads.count <= CodexObservationReducer.maxThreads else { continue }
            for thread in snapshot.threads {
                guard CodexObservationReducer.identifier(thread.id) != nil, CodexObservationReducer.identifier(thread.turnID) != nil,
                      ["running", "ended", "failed", "interrupted"].contains(thread.state), thread.timestamp.isFinite,
                      thread.timestamp <= snapshot.timestamp, thread.approvals.count <= 32, thread.blockingQuestions.count <= 32,
                      thread.questions.count <= 16 else { continue }
                if (newest[thread.id]?.0 ?? -.infinity) < thread.timestamp { newest[thread.id] = (thread.timestamp, thread) }
            }
        }
        return newest.values.map(\.1).sorted { $0.id < $1.id }
    }

    private static func pruneExpiredProjection(_ url: URL, now: Double) {
        guard url.lastPathComponent.range(of: #"^[0-9]+-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.json$"#, options: .regularExpression) != nil else { return }
        var before = stat()
        guard lstat(url.path, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_uid == getuid(), before.st_mode & 0o077 == 0,
              now - Double(before.st_mtimespec.tv_sec) * 1000 > 15_000 else { return }
        // Writer atomically renames; refuse to delete if its generation changed.
        var current = stat()
        guard lstat(url.path, &current) == 0, before.st_dev == current.st_dev, before.st_ino == current.st_ino,
              before.st_mtimespec.tv_sec == current.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == current.st_mtimespec.tv_nsec else { return }
        _ = unlink(url.path)
    }
}
