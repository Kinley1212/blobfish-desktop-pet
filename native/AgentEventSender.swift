import Darwin
import CryptoKit
import Foundation

private let maximumInputBytes = 2 * 1024 * 1024
private let maximumLeaseBytes = 16 * 1024
private let allowedProviders = Set(["codex", "claude-code"])
private let activeEvents = Set(["started", "running", "needs_input"])
private let terminalEvents = Set(["ended", "completed", "failed"])

private func argument(after flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag),
          CommandLine.arguments.indices.contains(index + 1) else { return nil }
    return CommandLine.arguments[index + 1]
}

private func hasPendingClaudeWork(_ input: [String: Any]) -> Bool {
    let backgroundTasks = input["background_tasks"] as? [[String: Any]] ?? []
    let sessionCrons = input["session_crons"] as? [[String: Any]] ?? []
    return !backgroundTasks.isEmpty || !sessionCrons.isEmpty
}

private func mappedEvent(_ hookName: String, input: [String: Any], provider: String) -> String? {
    switch hookName {
    case "UserPromptSubmit": return "started"
    case "PermissionRequest": return "needs_input"
    case "PostToolUse", "PostToolUseFailure": return "running"
    case "StopFailure": return "failed"
    case "Stop":
        if provider == "claude-code" && hasPendingClaudeWork(input) { return "running" }
        return "ended"
    case "SessionEnd": return "ended"
    case "Notification":
        guard provider == "claude-code",
              let notificationType = input["notification_type"] as? String else { return nil }
        if ["agent_needs_input", "permission_prompt", "elicitation_dialog"].contains(notificationType) {
            return "needs_input"
        }
        if notificationType == "idle_prompt" { return "ended" }
        return nil
    default: return nil
    }
}

private func readBoundedInput() -> Data? {
    var input = Data()
    while true {
        let chunk = FileHandle.standardInput.availableData
        if chunk.isEmpty { return input }
        guard input.count + chunk.count <= maximumInputBytes else { return nil }
        input.append(chunk)
    }
}

private func taskTitlesEnabled(settingsPath: String) -> Bool {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: settingsPath),
          let size = attributes[.size] as? NSNumber,
          size.intValue <= 256 * 1024,
          let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
          let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let privacy = settings["privacy"] as? [String: Any] else { return false }
    return privacy["includeTaskTitles"] as? Bool == true
}

private func validIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty, value.utf8.count <= 256 else { return false }
    return value.range(
        of: #"^[A-Za-z0-9._:@+\-]+$"#,
        options: .regularExpression
    ) != nil
}

private func replacingMatches(_ pattern: String, in source: String, with replacement: String = " ") -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return source
    }
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    return expression.stringByReplacingMatches(in: source, options: [], range: range, withTemplate: replacement)
}

private func titleSource(from source: String) -> String {
    let markers = ["My request for Codex:", "My request for Claude Code:", "My request:"]
    for marker in markers {
        if let range = source.range(of: marker, options: [.caseInsensitive]) {
            return String(source[range.upperBound...])
        }
    }
    return source
}

private func looksLikeAttachmentMetadata(_ line: String) -> Bool {
    let lowercased = line.lowercased()
    if lowercased.hasPrefix("# files mentioned by the user")
        || lowercased.hasPrefix("<image")
        || lowercased.hasPrefix("</image")
        || lowercased.contains("codex-clipboard-")
        || lowercased.contains("remote-attachments/")
        || lowercased.hasPrefix("file://")
        || lowercased.hasPrefix("/users/")
        || lowercased.hasPrefix("/tmp/")
        || lowercased.hasPrefix("/private/")
        || lowercased.hasPrefix("/var/") {
        return true
    }
    if lowercased.hasPrefix("## ") && (lowercased.contains(": /") || lowercased.contains(".png") || lowercased.contains(".jpg") || lowercased.contains(".jpeg")) {
        return true
    }
    return false
}

private func looksLikeOpaqueIdentifier(_ source: String) -> Bool {
    let compact = source.replacingOccurrences(of: " ", with: "")
    if compact.range(of: #"^[0-9a-f]{8}-[0-9a-f-]{27,}$"#, options: [.regularExpression, .caseInsensitive]) != nil {
        return true
    }
    let usefulScalars = source.unicodeScalars.filter { CharacterSet.letters.contains($0) }
    let punctuationCount = source.unicodeScalars.filter {
        CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
    }.count
    return usefulScalars.isEmpty || punctuationCount > usefulScalars.count * 3
}

private func sanitizedTitle(from source: String, provider: String) -> String {
    let containsAttachment = source.range(of: "Files mentioned by the user", options: [.caseInsensitive]) != nil
        || source.range(of: "<image", options: [.caseInsensitive]) != nil
        || source.contains("/remote-attachments/")
        || source.contains("codex-clipboard-")
    var cleaned = titleSource(from: source)
    cleaned = replacingMatches(#"<image\b[^>]*>[\s\S]*?</image>"#, in: cleaned)
    cleaned = replacingMatches(#"<image\b[^>]*/?>"#, in: cleaned)
    cleaned = replacingMatches(#"\{[\s\S]*?\"(?:attachment|file|path|image)[\s\S]*?\}"#, in: cleaned)

    let meaningfulLines = cleaned.components(separatedBy: .newlines).compactMap { rawLine -> String? in
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !looksLikeAttachmentMetadata(line) else { return nil }
        let withoutHeading = line.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
        guard !withoutHeading.isEmpty, !looksLikeOpaqueIdentifier(withoutHeading) else { return nil }
        return withoutHeading
    }
    let normalized = meaningfulLines.joined(separator: " ")
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    if normalized.isEmpty {
        let providerName = provider == "claude-code" ? "Claude Code" : "Codex"
        return containsAttachment ? "\(providerName) 附件任务" : "\(providerName) 任务"
    }
    if normalized.count <= 72 { return normalized }
    return String(normalized.prefix(71)) + "…"
}

private func taskTitle(from input: [String: Any], enabled: Bool, provider: String) -> String? {
    guard enabled else { return nil }
    let candidates = [input["title"], input["task_title"], input["prompt"]]
    guard let source = candidates.compactMap({ $0 as? String }).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
        return nil
    }
    return sanitizedTitle(from: source, provider: provider)
}

private func leaseURL(directoryPath: String, provider: String, sessionID: String) -> URL {
    let key = Data("\(provider)\u{0}\(sessionID)".utf8)
    let digest = SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
    return URL(fileURLWithPath: directoryPath, isDirectory: true)
        .appendingPathComponent("\(digest).json", isDirectory: false)
}

private func readLease(at url: URL) -> [String: Any]? {
    let manager = FileManager.default
    guard let attributes = try? manager.attributesOfItem(atPath: url.path),
          attributes[.type] as? FileAttributeType == .typeRegular,
          let size = attributes[.size] as? NSNumber,
          size.intValue <= maximumLeaseBytes,
          let data = try? Data(contentsOf: url),
          let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    return value
}

private func matchingTurn(existing: [String: Any], incoming: [String: Any]) -> Bool {
    guard let incomingTurn = incoming["turnId"] as? String else { return true }
    return existing["turnId"] as? String == incomingTurn
}

private func inheritedTurnID(
    directoryPath: String,
    provider: String,
    sessionID: String
) -> String? {
    let url = leaseURL(directoryPath: directoryPath, provider: provider, sessionID: sessionID)
    guard let existing = readLease(at: url),
          activeEvents.contains(existing["event"] as? String ?? ""),
          existing["provider"] as? String == provider,
          existing["sessionId"] as? String == sessionID,
          let turnID = existing["turnId"] as? String,
          validIdentifier(turnID) else {
        return nil
    }
    return turnID
}

private func writeLease(
    directoryPath: String,
    payload: [String: Any],
    event: String,
    includeTaskTitles: Bool
) {
    let manager = FileManager.default
    let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
    do {
        try manager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        try manager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directoryURL.path
        )
    } catch {
        return
    }

    guard let provider = payload["provider"] as? String,
          let sessionID = payload["sessionId"] as? String else { return }
    let url = leaseURL(directoryPath: directoryPath, provider: provider, sessionID: sessionID)
    let existing = readLease(at: url)

    if terminalEvents.contains(event) {
        if let existing, !matchingTurn(existing: existing, incoming: payload) { return }
    }

    guard activeEvents.contains(event) || terminalEvents.contains(event) else { return }
    if event != "started" {
        if activeEvents.contains(event) {
            guard let existing,
                  activeEvents.contains(existing["event"] as? String ?? ""),
                  existing["provider"] as? String == provider,
                  existing["sessionId"] as? String == sessionID,
                  matchingTurn(existing: existing, incoming: payload) else {
                return
            }
        }
    }

    var lease = payload
    if event == "started" {
        lease["startedAt"] = payload["timestamp"]
    } else if let existing {
        lease["startedAt"] = existing["startedAt"] ?? existing["timestamp"] ?? payload["timestamp"]
        if lease["turnId"] == nil, let turnID = existing["turnId"] as? String {
            lease["turnId"] = turnID
        }
        if includeTaskTitles, lease["title"] == nil, let title = existing["title"] as? String {
            lease["title"] = title
        }
    }
    if !includeTaskTitles { lease.removeValue(forKey: "title") }

    guard let data = try? JSONSerialization.data(withJSONObject: lease),
          data.count <= maximumLeaseBytes else { return }
    do {
        try data.write(to: url, options: .atomic)
        try manager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    } catch {
        // Another sender may already have atomically replaced this session's
        // snapshot. Never delete the shared target after our own write fails.
        return
    }
}

private func sendToUnixSocket(path: String, data: Data) {
    var address = sockaddr_un()
    let pathBytes = Array(path.utf8CString)
    let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count <= pathCapacity else { return }

    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    path.withCString { source in
        withUnsafeMutablePointer(to: &address.sun_path.0) { destination in
            _ = Darwin.strlcpy(destination, source, pathCapacity)
        }
    }

    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return }
    defer { Darwin.close(descriptor) }
    Darwin.signal(SIGPIPE, SIG_IGN)

    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { return }

    var message = data
    message.append(Data("\n".utf8))
    message.withUnsafeBytes { rawBuffer in
        guard var pointer = rawBuffer.baseAddress else { return }
        var remaining = rawBuffer.count
        while remaining > 0 {
            let written = Darwin.write(descriptor, pointer, remaining)
            if written <= 0 { return }
            remaining -= written
            pointer = pointer.advanced(by: written)
        }
    }
}

@main
private struct AgentEventSender {
    static func main() {
        _ = Darwin.umask(0o077)
        guard let provider = argument(after: "--provider"), allowedProviders.contains(provider) else { return }
        guard let inputData = readBoundedInput(), !inputData.isEmpty,
              let input = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
              let hookName = input["hook_event_name"] as? String,
              let event = mappedEvent(hookName, input: input, provider: provider),
              let sessionID = input["session_id"] as? String,
              validIdentifier(sessionID) else { return }
        let inputTurnID = input["turn_id"] as? String
        guard inputTurnID == nil || validIdentifier(inputTurnID!) else { return }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let socketPath = ProcessInfo.processInfo.environment["BLOBFISH_SOCKET"]
            ?? home + "/Library/Application Support/BlobfishDesktopPet/agent-events.sock"
        let settingsPath = ProcessInfo.processInfo.environment["BLOBFISH_SETTINGS"]
            ?? URL(fileURLWithPath: socketPath).deletingLastPathComponent().appendingPathComponent("settings.json").path
        let leaseDirectoryPath = ProcessInfo.processInfo.environment["BLOBFISH_TASK_LEASES"]
            ?? URL(fileURLWithPath: socketPath).deletingLastPathComponent().appendingPathComponent("agent-task-leases").path
        let includeTaskTitles = taskTitlesEnabled(settingsPath: settingsPath)
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let turnID: String?
        if let inputTurnID {
            turnID = inputTurnID
        } else if event == "started" {
            turnID = "blobfish-\(UUID().uuidString.lowercased())"
        } else {
            turnID = inheritedTurnID(
                directoryPath: leaseDirectoryPath,
                provider: provider,
                sessionID: sessionID
            )
        }

        var payload: [String: Any] = [
            "version": 1,
            "provider": provider,
            "event": event,
            "sessionId": sessionID,
            "timestamp": timestamp,
        ]
        if let turnID { payload["turnId"] = turnID }
        if let title = taskTitle(from: input, enabled: includeTaskTitles, provider: provider) {
            payload["title"] = title
        }
        writeLease(
            directoryPath: leaseDirectoryPath,
            payload: payload,
            event: event,
            includeTaskTitles: includeTaskTitles
        )
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload) else { return }
        sendToUnixSocket(path: socketPath, data: encoded)
        if provider == "codex" && hookName == "Stop" {
            FileHandle.standardOutput.write(Data("{}\n".utf8))
        }
    }
}
