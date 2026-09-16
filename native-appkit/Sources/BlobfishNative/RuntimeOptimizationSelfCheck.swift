import AppKit
import Darwin

extension SelfCheck {
    static func decodeCachePreservesFileSafety() throws -> Bool {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blobfish-cache-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("value.json")
        func write(_ value: String) throws {
            try Data(value.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        let cache = PrivateFileDecodeCache<Int>(maximumEntries: 2, maximumSourceBytes: 16)
        var decodes = 0
        func load() -> Int? {
            cache.load(url, maximumFileBytes: 64) {
                decodes += 1
                return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Int.self, from: $0) }
            }
        }
        try write("11")
        for _ in 0..<500 { guard load() == 11 else { return false } }
        guard decodes == 1 else { return false }
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]
        // Same-size in-place write, even with the original mtime restored.
        let handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Data("22".utf8)); try handle.close()
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        guard load() == 22, decodes == 2 else { return false }
        try write("33")
        guard load() == 33, decodes == 3 else { return false }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        guard load() == nil, cache.count == 0, decodes == 3 else { return false }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        guard load() == nil, cache.count == 0, decodes == 3 else { return false }
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: root.appendingPathComponent("missing"))
        guard load() == nil, decodes == 3 else { return false }
        try FileManager.default.removeItem(at: url)
        guard mkfifo(url.path, 0o600) == 0, load() == nil, decodes == 3 else { return false }
        try FileManager.default.removeItem(at: url)
        guard load() == nil else { return false }
        try write("44")
        guard load() == 44 else { return false }
        cache.retainOnly([])
        guard cache.count == 0, cache.sourceBytes == 0 else { return false }
        let tiny = PrivateFileDecodeCache<Int>(maximumEntries: 1, maximumSourceBytes: 1)
        guard tiny.load(url, maximumFileBytes: 64, read: { 44 }) == 44,
              tiny.count == 0 else { return false }
        for index in 0..<4 {
            let other = root.appendingPathComponent("\(index).json")
            try Data("1".utf8).write(to: other)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: other.path)
            guard cache.load(other, maximumFileBytes: 64, read: { 1 }) == 1 else { return false }
        }
        return cache.count == 2 && cache.sourceBytes == 2
    }

    static func cachedTasksStillExpire() throws -> Bool {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blobfish-expiry-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date().timeIntervalSince1970 * 1000
        let leaseURL = root.appendingPathComponent(String(repeating: "a", count: 64) + ".json")
        let lease: [String: Any] = ["version": 1, "provider": "codex", "sessionId": "test", "event": "running", "timestamp": now]
        try JSONSerialization.data(withJSONObject: lease).write(to: leaseURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: leaseURL.path)
        let cache = PrivateFileDecodeCache<TaskLease>(maximumEntries: 4, maximumSourceBytes: 4096)
        let reader = TaskLeaseReader(directoryURL: root)
        guard try reader.read(nowMilliseconds: now, cache: cache).count == 1,
              try reader.read(nowMilliseconds: now + 1000, cache: cache).count == 1,
              try reader.read(nowMilliseconds: now + 1_800_001, cache: cache).isEmpty,
              cache.count == 0 else { return false }
        let snapshotURL = root.appendingPathComponent("observer.json")
        let snapshot = CodexObservationSnapshot(timestamp: now, threads: [
            CodexObservedThread(id: "test", turnID: "turn", state: "running", timestamp: now, approvals: ["s:approval"])
        ])
        guard CodexObservationFiles.write(try JSONEncoder().encode(snapshot), to: snapshotURL) else { return false }
        let snapshots = PrivateFileDecodeCache<CodexObservationSnapshot>(maximumEntries: 4, maximumSourceBytes: 4096)
        var decodes = 0
        let read: (URL) -> CodexObservationSnapshot? = { url in
            snapshots.load(url, maximumFileBytes: CodexObservationFiles.maximumBytes) {
                decodes += 1
                return CodexObservationFiles.read(url).flatMap { try? JSONDecoder().decode(CodexObservationSnapshot.self, from: $0) }
            }
        }
        try FileManager.default.removeItem(at: leaseURL)
        guard CodexObservationFiles.load(directory: root, now: now, readSnapshot: read).first?.approvals == ["s:approval"],
              CodexObservationFiles.load(directory: root, now: now + 1000, readSnapshot: read).count == 1,
              CodexObservationFiles.load(directory: root, now: now + 6001, readSnapshot: read).isEmpty,
              decodes == 1 else { return false }
        return true
    }

    static func sharedFramesRespectSubscriberLifecycle() -> Bool {
        let frames = FrameSubscribers()
        var seen: [String] = []
        var second: UUID?
        var replacement: UUID?
        let first = frames.add { uptime in
            seen.append("first:\(Int(uptime))")
            if let second { frames.remove(second) }
            if replacement == nil {
                replacement = frames.add { time in seen.append("new:\(Int(time))") }
            }
        }
        second = frames.add { _ in seen.append("removed") }
        frames.deliver(1)
        frames.deliver(2)
        frames.remove(first)
        if let replacement { frames.remove(replacement) }
        frames.deliver(3)
        return frames.isEmpty && seen == ["first:1", "first:2", "new:2"]
    }

    static func effectTimelinesPreserveDuration() -> Bool {
        for duration in [0.32, 0.44, 0.5, 0.52, 0.7, 1.4, 1.7, 2.0] {
            let timeline = PetAnimationTimeline(duration: duration, startedAt: 0)
            for fps in [30.0, 60.0, 120.0] {
                for tick in 0...Int(ceil(duration * fps)) {
                    let time = Double(tick) / fps
                    guard abs(Double(timeline.progress(at: time)) - min(1, time / duration)) < 0.000001 else { return false }
                }
            }
            guard timeline.progress(at: -1) == 0,
                  timeline.progress(at: duration) == 1,
                  timeline.progress(at: duration + 60) == 1 else { return false }
        }
        return true
    }
}
