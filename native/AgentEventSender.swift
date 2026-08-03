import Darwin
import CryptoKit
import Foundation

private let maximumInputBytes = 2 * 1024 * 1024
private let maximumLeaseBytes = 16 * 1024
private let maximumFutureTimestampSkewMs: Int64 = 60 * 1000
private let startedLeaseMaxAgeMs: Int64 = 15 * 60 * 1000
private let runningLeaseMaxAgeMs: Int64 = 30 * 60 * 1000
private let terminalLeaseMaxAgeMs: Int64 = 5 * 60 * 1000
private let waitingLeaseMaxAgeMs: Int64 = 8 * 60 * 60 * 1000
private let sessionLockAttempts = 10
private let sessionLockRetryMicroseconds: useconds_t = 5_000
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

private func sessionDigest(provider: String, sessionID: String) -> String {
    let key = Data("\(provider)\u{0}\(sessionID)".utf8)
    return SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
}

private func wallClockMilliseconds() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}

private func monotonicNanoseconds() -> UInt64 {
    var time = timespec()
    guard Darwin.clock_gettime(CLOCK_MONOTONIC_RAW, &time) == 0 else { return 0 }
    return UInt64(time.tv_sec) * 1_000_000_000 + UInt64(time.tv_nsec)
}

private func bootTimeSeconds() -> Int64? {
    var value = timeval()
    var size = MemoryLayout<timeval>.size
    guard Darwin.sysctlbyname("kern.boottime", &value, &size, nil, 0) == 0 else {
        return nil
    }
    return Int64(value.tv_sec)
}

private func privateOwnedDirectory(_ info: stat) -> Bool {
    (info.st_mode & S_IFMT) == S_IFDIR
        && info.st_uid == Darwin.geteuid()
        && (info.st_mode & 0o077) == 0
}

private func privateOwnedRegularFile(_ info: stat) -> Bool {
    (info.st_mode & S_IFMT) == S_IFREG
        && info.st_uid == Darwin.geteuid()
        && (info.st_mode & 0o077) == 0
}

private func openSecureLeaseDirectory(path: String) -> Int32? {
    let manager = FileManager.default
    var existing = stat()
    if Darwin.lstat(path, &existing) == 0 {
        guard privateOwnedDirectory(existing) else { return nil }
    } else {
        guard errno == ENOENT else { return nil }
        do {
            try manager.createDirectory(
                at: URL(fileURLWithPath: path, isDirectory: true),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
            )
        } catch {
            return nil
        }
    }

    let descriptor = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { return nil }
    var opened = stat()
    guard Darwin.fstat(descriptor, &opened) == 0, privateOwnedDirectory(opened) else {
        Darwin.close(descriptor)
        return nil
    }
    return descriptor
}

private func acquireSessionLock(directoryDescriptor: Int32, name: String) -> Int32? {
    let descriptor = Darwin.openat(
        directoryDescriptor,
        name,
        O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC,
        mode_t(0o600)
    )
    guard descriptor >= 0 else { return nil }
    var info = stat()
    guard Darwin.fstat(descriptor, &info) == 0, privateOwnedRegularFile(info) else {
        Darwin.close(descriptor)
        return nil
    }
    var lock = flock()
    lock.l_type = Int16(F_WRLCK)
    lock.l_whence = Int16(SEEK_SET)
    for attempt in 0..<sessionLockAttempts {
        if Darwin.fcntl(descriptor, F_SETLK, &lock) == 0 {
            return descriptor
        }
        guard errno == EINTR || errno == EACCES || errno == EAGAIN else {
            Darwin.close(descriptor)
            return nil
        }
        if attempt + 1 < sessionLockAttempts {
            Darwin.usleep(sessionLockRetryMicroseconds)
        }
    }
    Darwin.close(descriptor)
    return nil
}

private enum LeaseReadResult {
    case missing
    case valid([String: Any])
    case invalid
}

private func boundedData(from descriptor: Int32) -> Data? {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = buffer.withUnsafeMutableBytes { rawBuffer in
            Darwin.read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
        }
        if count == 0 { return data }
        if count < 0 {
            if errno == EINTR { continue }
            return nil
        }
        guard data.count + count <= maximumLeaseBytes else { return nil }
        data.append(contentsOf: buffer.prefix(count))
    }
}

private func readLease(directoryDescriptor: Int32, name: String) -> LeaseReadResult {
    let descriptor = Darwin.openat(directoryDescriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    if descriptor < 0 {
        return errno == ENOENT ? .missing : .invalid
    }
    defer { Darwin.close(descriptor) }

    var info = stat()
    guard Darwin.fstat(descriptor, &info) == 0,
          privateOwnedRegularFile(info),
          info.st_size >= 0,
          info.st_size <= maximumLeaseBytes,
          let data = boundedData(from: descriptor),
          let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return .invalid
    }
    return .valid(value)
}

private func matchingTurn(existing: [String: Any], incoming: [String: Any]) -> Bool {
    guard let incomingTurn = incoming["turnId"] as? String else { return true }
    return existing["turnId"] as? String == incomingTurn
}

private func validLeaseTarget(directoryDescriptor: Int32, name: String) -> Bool {
    var info = stat()
    if Darwin.fstatat(directoryDescriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
        return privateOwnedRegularFile(info)
    }
    return errno == ENOENT
}

private func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
    data.withUnsafeBytes { rawBuffer in
        guard var pointer = rawBuffer.baseAddress else { return data.isEmpty }
        var remaining = rawBuffer.count
        while remaining > 0 {
            let written = Darwin.write(descriptor, pointer, remaining)
            if written < 0, errno == EINTR { continue }
            guard written > 0 else { return false }
            remaining -= written
            pointer = pointer.advanced(by: written)
        }
        return true
    }
}

private func writeLeaseAtomically(
    directoryDescriptor: Int32,
    name: String,
    data: Data
) -> Bool {
    guard validLeaseTarget(directoryDescriptor: directoryDescriptor, name: name) else { return false }
    let temporaryName = ".\(name).\(Darwin.getpid()).\(UUID().uuidString.lowercased()).tmp"
    let descriptor = Darwin.openat(
        directoryDescriptor,
        temporaryName,
        O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC,
        mode_t(0o600)
    )
    guard descriptor >= 0 else { return false }

    var shouldRemoveTemporary = true
    defer {
        Darwin.close(descriptor)
        if shouldRemoveTemporary {
            _ = Darwin.unlinkat(directoryDescriptor, temporaryName, 0)
        }
    }

    guard writeAll(data, to: descriptor),
          Darwin.fsync(descriptor) == 0,
          validLeaseTarget(directoryDescriptor: directoryDescriptor, name: name),
          Darwin.renameat(directoryDescriptor, temporaryName, directoryDescriptor, name) == 0 else {
        return false
    }
    shouldRemoveTemporary = false
    _ = Darwin.fsync(directoryDescriptor)
    return true
}

private func predatesCurrentGeneration(
    existing: [String: Any],
    timestamp: Int64,
    invocationMonotonicNs: UInt64,
    currentBootTimeSeconds: Int64?
) -> Bool {
    if let generation = existing["_generationStartedAtNs"] as? NSNumber,
       let generationBoot = existing["_generationBootTimeSeconds"] as? NSNumber,
       let currentBootTimeSeconds,
       generationBoot.int64Value == currentBootTimeSeconds,
       invocationMonotonicNs > 0 {
        return invocationMonotonicNs <= generation.uint64Value
    }
    if let startedAt = existing["startedAt"] as? NSNumber {
        return timestamp < startedAt.int64Value
    }
    return false
}

private func startedSupersedesExisting(
    existing: [String: Any],
    timestamp: Int64,
    invocationMonotonicNs: UInt64,
    currentBootTimeSeconds: Int64?
) -> Bool {
    if let generation = existing["_generationStartedAtNs"] as? NSNumber,
       let generationBoot = existing["_generationBootTimeSeconds"] as? NSNumber,
       let currentBootTimeSeconds,
       generationBoot.int64Value == currentBootTimeSeconds,
       invocationMonotonicNs > 0 {
        return invocationMonotonicNs > generation.uint64Value
    }
    let existingTimestamp = (existing["startedAt"] as? NSNumber)?.int64Value
        ?? (existing["timestamp"] as? NSNumber)?.int64Value
    return existingTimestamp == nil || timestamp > existingTimestamp!
}

private enum EventDecision {
    case deliver([String: Any])
    case reject
}

private func canDeliverWithoutLease(
    provider: String,
    hookName: String,
    event: String,
    inputTurnID: String?
) -> Bool {
    event == "started"
        || inputTurnID != nil
        || hookName == "SessionEnd"
        || (provider == "claude-code" && event == "needs_input")
}

private func persistEvent(
    directoryPath: String,
    payload: [String: Any],
    hookName: String,
    event: String,
    inputTurnID: String?,
    includeTaskTitles: Bool,
    invocationMonotonicNs: UInt64,
    currentBootTimeSeconds: Int64?
) -> EventDecision {
    guard let provider = payload["provider"] as? String,
          let sessionID = payload["sessionId"] as? String,
          let timestamp = payload["timestamp"] as? Int64,
          activeEvents.contains(event) || terminalEvents.contains(event) else {
        return .reject
    }

    var outbound = payload
    if event == "started" {
        outbound["turnId"] = inputTurnID ?? "blobfish-\(UUID().uuidString.lowercased())"
    } else if let inputTurnID {
        outbound["turnId"] = inputTurnID
    }

    if provider == "claude-code",
       inputTurnID == nil,
       event != "started",
       hookName != "SessionEnd" {
        // Current Claude Code hooks expose prompt_id for once-per-turn events.
        // Older clients do not provide enough information to attach a late
        // running/terminal event to a generation safely. Standalone approval
        // notifications may still inform a live pet without mutating a lease.
        return event == "needs_input" ? .deliver(outbound) : .reject
    }
    let canFallbackToSocket = canDeliverWithoutLease(
        provider: provider,
        hookName: hookName,
        event: event,
        inputTurnID: inputTurnID
    )

    guard let directoryDescriptor = openSecureLeaseDirectory(path: directoryPath) else {
        return canFallbackToSocket ? .deliver(outbound) : .reject
    }
    defer { Darwin.close(directoryDescriptor) }

    let digest = sessionDigest(provider: provider, sessionID: sessionID)
    guard let lockDescriptor = acquireSessionLock(
        directoryDescriptor: directoryDescriptor,
        name: "\(digest).lock"
    ) else {
        return canFallbackToSocket ? .deliver(outbound) : .reject
    }
    defer {
        var lock = flock()
        lock.l_type = Int16(F_UNLCK)
        lock.l_whence = Int16(SEEK_SET)
        _ = Darwin.fcntl(lockDescriptor, F_SETLK, &lock)
        Darwin.close(lockDescriptor)
    }

    let leaseName = "\(digest).json"
    let existing: [String: Any]?
    switch readLease(directoryDescriptor: directoryDescriptor, name: leaseName) {
    case .missing:
        existing = nil
    case .valid(let value):
        guard value["provider"] as? String == provider,
              value["sessionId"] as? String == sessionID else {
            return canFallbackToSocket ? .deliver(outbound) : .reject
        }
        existing = value
    case .invalid:
        // A complete new turn may safely replace a corrupt private regular
        // snapshot while holding this session's lock. Other lifecycle events
        // cannot establish which generation the damaged file belonged to.
        guard event == "started" else {
            return canFallbackToSocket ? .deliver(outbound) : .reject
        }
        existing = nil
    }

    if event == "started" {
        if let existing {
            let existingTurnID = existing["turnId"] as? String
            if inputTurnID != nil,
               existingTurnID == inputTurnID {
                return .reject
            }
            if !startedSupersedesExisting(
                existing: existing,
                timestamp: timestamp,
                invocationMonotonicNs: invocationMonotonicNs,
                currentBootTimeSeconds: currentBootTimeSeconds
            ) {
                return .reject
            }
        }
    } else if let existing {
        guard inputTurnID != nil || !predatesCurrentGeneration(
            existing: existing,
            timestamp: timestamp,
            invocationMonotonicNs: invocationMonotonicNs,
            currentBootTimeSeconds: currentBootTimeSeconds
        ) else {
            return .reject
        }
        if inputTurnID != nil {
            guard matchingTurn(existing: existing, incoming: outbound) else { return .reject }
        } else if let turnID = existing["turnId"] as? String, validIdentifier(turnID) {
            outbound["turnId"] = turnID
        }
    }

    if event != "started", activeEvents.contains(event) {
        guard let existing,
              activeEvents.contains(existing["event"] as? String ?? ""),
              matchingTurn(existing: existing, incoming: outbound) else {
            // Keep standalone notifications useful to a running app without
            // inventing a recoverable task when no active generation exists.
            return existing == nil && canFallbackToSocket ? .deliver(outbound) : .reject
        }
    }

    var lease = outbound
    if event == "started" {
        lease["startedAt"] = timestamp
        lease["_generationStartedAtNs"] = NSNumber(value: invocationMonotonicNs)
        if let currentBootTimeSeconds {
            lease["_generationBootTimeSeconds"] = NSNumber(value: currentBootTimeSeconds)
        }
    } else if let existing {
        lease["startedAt"] = existing["startedAt"] ?? existing["timestamp"] ?? timestamp
        if let generation = existing["_generationStartedAtNs"] {
            lease["_generationStartedAtNs"] = generation
        }
        if let generationBoot = existing["_generationBootTimeSeconds"] {
            lease["_generationBootTimeSeconds"] = generationBoot
        }
        if lease["turnId"] == nil, let turnID = existing["turnId"] as? String {
            lease["turnId"] = turnID
        }
        if includeTaskTitles, lease["title"] == nil, let title = existing["title"] as? String {
            lease["title"] = title
        }
    }
    if terminalEvents.contains(event) || !includeTaskTitles {
        lease.removeValue(forKey: "title")
    }

    guard let data = try? JSONSerialization.data(withJSONObject: lease),
          data.count <= maximumLeaseBytes else {
        return canFallbackToSocket ? .deliver(outbound) : .reject
    }
    if !writeLeaseAtomically(
        directoryDescriptor: directoryDescriptor,
        name: leaseName,
        data: data
    ) {
        return canFallbackToSocket ? .deliver(outbound) : .reject
    }
    return .deliver(outbound)
}

private struct LeaseFileSnapshot {
    let info: stat
    let value: [String: Any]?
}

private func leaseFileNames(directoryDescriptor: Int32) -> [String] {
    let duplicated = Darwin.dup(directoryDescriptor)
    guard duplicated >= 0, let directory = Darwin.fdopendir(duplicated) else {
        if duplicated >= 0 { Darwin.close(duplicated) }
        return []
    }
    defer { Darwin.closedir(directory) }

    var names: [String] = []
    while let entry = Darwin.readdir(directory) {
        let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                String(cString: $0)
            }
        }
        guard name.count == 69, name.hasSuffix(".json") else { continue }
        let digest = name.dropLast(5)
        guard digest.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { continue }
        names.append(name)
    }
    return names
}

private func readLeaseSnapshot(
    directoryDescriptor: Int32,
    name: String
) -> LeaseFileSnapshot? {
    let descriptor = Darwin.openat(directoryDescriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { return nil }
    defer { Darwin.close(descriptor) }

    var info = stat()
    guard Darwin.fstat(descriptor, &info) == 0, privateOwnedRegularFile(info) else {
        return nil
    }
    guard info.st_size >= 0, info.st_size <= maximumLeaseBytes,
          let data = boundedData(from: descriptor),
          let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return LeaseFileSnapshot(info: info, value: nil)
    }
    return LeaseFileSnapshot(info: info, value: value)
}

private func shouldPruneLease(
    value: [String: Any]?,
    digest: String,
    now: Int64
) -> Bool {
    guard let value,
          let version = value["version"] as? NSNumber,
          version.intValue == 1,
          let provider = value["provider"] as? String,
          allowedProviders.contains(provider),
          let event = value["event"] as? String,
          activeEvents.contains(event) || terminalEvents.contains(event),
          let sessionID = value["sessionId"] as? String,
          validIdentifier(sessionID),
          sessionDigest(provider: provider, sessionID: sessionID) == digest,
          let timestampNumber = value["timestamp"] as? NSNumber,
          timestampNumber.doubleValue.isFinite,
          timestampNumber.doubleValue >= 0,
          timestampNumber.doubleValue <= Double(Int64.max) else {
        return true
    }
    if let turnID = value["turnId"] {
        guard let turnID = turnID as? String, validIdentifier(turnID) else { return true }
    }

    let timestamp = timestampNumber.int64Value
    if timestamp > now + maximumFutureTimestampSkewMs { return true }
    if timestamp > now { return false }
    let maxAge: Int64
    if terminalEvents.contains(event) {
        maxAge = terminalLeaseMaxAgeMs
    } else if event == "needs_input" {
        maxAge = waitingLeaseMaxAgeMs
    } else if event == "started" {
        maxAge = startedLeaseMaxAgeMs
    } else {
        maxAge = runningLeaseMaxAgeMs
    }
    return now - timestamp > maxAge
}

private func sameFile(_ left: stat, _ right: stat) -> Bool {
    left.st_dev == right.st_dev
        && left.st_ino == right.st_ino
        && left.st_size == right.st_size
        && left.st_mtimespec.tv_sec == right.st_mtimespec.tv_sec
        && left.st_mtimespec.tv_nsec == right.st_mtimespec.tv_nsec
}

private func removeLeaseIfUnchanged(
    directoryDescriptor: Int32,
    name: String,
    expected: stat
) {
    var current = stat()
    guard Darwin.fstatat(directoryDescriptor, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
          privateOwnedRegularFile(current),
          sameFile(current, expected) else {
        return
    }
    _ = Darwin.unlinkat(directoryDescriptor, name, 0)
}

private func pruneLeases(directoryPath: String, now: Int64 = wallClockMilliseconds()) {
    guard let directoryDescriptor = openSecureLeaseDirectory(path: directoryPath) else { return }
    defer { Darwin.close(directoryDescriptor) }

    for name in leaseFileNames(directoryDescriptor: directoryDescriptor) {
        do {
            let digest = String(name.dropLast(5))
            guard let lockDescriptor = acquireSessionLock(
                directoryDescriptor: directoryDescriptor,
                name: "\(digest).lock"
            ) else {
                continue
            }
            defer {
                var lock = flock()
                lock.l_type = Int16(F_UNLCK)
                lock.l_whence = Int16(SEEK_SET)
                _ = Darwin.fcntl(lockDescriptor, F_SETLK, &lock)
                Darwin.close(lockDescriptor)
            }

            guard let snapshot = readLeaseSnapshot(
                directoryDescriptor: directoryDescriptor,
                name: name
            ), shouldPruneLease(value: snapshot.value, digest: digest, now: now) else {
                continue
            }
            removeLeaseIfUnchanged(
                directoryDescriptor: directoryDescriptor,
                name: name,
                expected: snapshot.info
            )
        }
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
        if CommandLine.arguments.contains("--prune") {
            guard let directoryPath = argument(after: "--lease-directory"),
                  directoryPath.hasPrefix("/"),
                  directoryPath.utf8.count <= 1024 else {
                return
            }
            pruneLeases(directoryPath: directoryPath)
            return
        }

        let timestamp = wallClockMilliseconds()
        let invocationMonotonicNs = monotonicNanoseconds()
        let currentBootTimeSeconds = bootTimeSeconds()
        guard let provider = argument(after: "--provider"), allowedProviders.contains(provider) else { return }
        guard let inputData = readBoundedInput(), !inputData.isEmpty,
              let input = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
              let hookName = input["hook_event_name"] as? String,
              let event = mappedEvent(hookName, input: input, provider: provider),
              let sessionID = input["session_id"] as? String,
              validIdentifier(sessionID) else { return }
        let turnField = provider == "claude-code" ? "prompt_id" : "turn_id"
        let inputTurnValue = input[turnField]
        guard inputTurnValue == nil || inputTurnValue is String else { return }
        let inputTurnID = inputTurnValue as? String
        guard inputTurnID == nil || validIdentifier(inputTurnID!) else { return }
        defer {
            if provider == "codex" && hookName == "Stop" {
                FileHandle.standardOutput.write(Data("{}\n".utf8))
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let socketPath = ProcessInfo.processInfo.environment["BLOBFISH_SOCKET"]
            ?? home + "/Library/Application Support/BlobfishDesktopPet/agent-events.sock"
        let settingsPath = ProcessInfo.processInfo.environment["BLOBFISH_SETTINGS"]
            ?? URL(fileURLWithPath: socketPath).deletingLastPathComponent().appendingPathComponent("settings.json").path
        let leaseDirectoryPath = ProcessInfo.processInfo.environment["BLOBFISH_TASK_LEASES"]
            ?? URL(fileURLWithPath: socketPath).deletingLastPathComponent().appendingPathComponent("agent-task-leases").path
        let includeTaskTitles = taskTitlesEnabled(settingsPath: settingsPath)

        var payload: [String: Any] = [
            "version": 1,
            "provider": provider,
            "event": event,
            "sessionId": sessionID,
            "timestamp": timestamp,
        ]
        if let title = taskTitle(from: input, enabled: includeTaskTitles, provider: provider) {
            payload["title"] = title
        }
        let decision = persistEvent(
            directoryPath: leaseDirectoryPath,
            payload: payload,
            hookName: hookName,
            event: event,
            inputTurnID: inputTurnID,
            includeTaskTitles: includeTaskTitles,
            invocationMonotonicNs: invocationMonotonicNs,
            currentBootTimeSeconds: currentBootTimeSeconds
        )
        guard case .deliver(let deliveredPayload) = decision,
              let encoded = try? JSONSerialization.data(withJSONObject: deliveredPayload) else {
            return
        }
        sendToUnixSocket(path: socketPath, data: encoded)
    }
}
