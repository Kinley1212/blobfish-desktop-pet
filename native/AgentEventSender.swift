import Darwin
import Foundation

private let maximumInputBytes = 2 * 1024 * 1024
private let allowedProviders = Set(["codex", "claude-code"])

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
        if notificationType == "agent_needs_input" { return "needs_input" }
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

private func taskTitle(from input: [String: Any], settingsPath: String, provider: String) -> String? {
    guard taskTitlesEnabled(settingsPath: settingsPath) else { return nil }
    let candidates = [input["title"], input["task_title"], input["prompt"]]
    guard let source = candidates.compactMap({ $0 as? String }).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
        return nil
    }
    return sanitizedTitle(from: source, provider: provider)
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
        guard let provider = argument(after: "--provider"), allowedProviders.contains(provider) else { return }
        guard let inputData = readBoundedInput(), !inputData.isEmpty,
              let input = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
              let hookName = input["hook_event_name"] as? String,
              let event = mappedEvent(hookName, input: input, provider: provider),
              let sessionID = input["session_id"] as? String,
              !sessionID.isEmpty else { return }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let socketPath = ProcessInfo.processInfo.environment["BLOBFISH_SOCKET"]
            ?? home + "/Library/Application Support/BlobfishDesktopPet/agent-events.sock"
        let settingsPath = ProcessInfo.processInfo.environment["BLOBFISH_SETTINGS"]
            ?? URL(fileURLWithPath: socketPath).deletingLastPathComponent().appendingPathComponent("settings.json").path

        var payload: [String: Any] = [
            "version": 1,
            "provider": provider,
            "event": event,
            "sessionId": sessionID,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
        ]
        if let turnID = input["turn_id"] as? String, !turnID.isEmpty { payload["turnId"] = turnID }
        if let title = taskTitle(from: input, settingsPath: settingsPath, provider: provider) { payload["title"] = title }
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload) else { return }
        sendToUnixSocket(path: socketPath, data: encoded)
    }
}
