import Darwin
import Foundation

enum TaskLeaseReaderError: Error {
    case insecureDirectory
}

struct TaskLeaseReader {
    static let maximumFileBytes = 16 * 1024
    static let maximumLeaseCount = 256
    static let maximumDirectoryEntries = 1_024
    static let startedMaximumAgeMilliseconds: Double = 15 * 60 * 1_000
    static let runningMaximumAgeMilliseconds: Double = 30 * 60 * 1_000
    static let waitingMaximumAgeMilliseconds: Double = 8 * 60 * 60 * 1_000
    static let terminalMaximumAgeMilliseconds: Double = 5 * 60 * 1_000

    let directoryURL: URL

    func read(nowMilliseconds: Double = Date().timeIntervalSince1970 * 1_000) throws -> [TaskLease] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        let directoryInfo = try metadata(atPath: directoryURL.path)
        guard isType(directoryInfo.st_mode, S_IFDIR),
              directoryInfo.st_uid == getuid(),
              directoryInfo.st_mode & 0o077 == 0 else {
            throw TaskLeaseReaderError.insecureDirectory
        }

        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
        let entries = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        guard entries.count <= Self.maximumDirectoryEntries else { return [] }

        let candidates = entries.compactMap { url -> (URL, Date)? in
            guard isLeaseName(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else { return nil }
            return (url, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.1 > $1.1 }

        var leases: [TaskLease] = []
        for (url, _) in candidates {
            if let lease = try readLease(at: url, nowMilliseconds: nowMilliseconds) {
                leases.append(lease)
                if leases.count >= Self.maximumLeaseCount { break }
            }
        }
        return leases.sorted { $0.timestamp < $1.timestamp }
    }

    private func readLease(at url: URL, nowMilliseconds: Double) throws -> TaskLease? {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        if descriptor < 0 {
            if errno == ENOENT || errno == ELOOP { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }

        var openedInfo = stat()
        guard fstat(descriptor, &openedInfo) == 0 else { throw POSIXError(.EIO) }
        guard isType(openedInfo.st_mode, S_IFREG),
              openedInfo.st_uid == getuid(),
              openedInfo.st_mode & 0o077 == 0,
              openedInfo.st_size >= 0,
              openedInfo.st_size <= Self.maximumFileBytes else { return nil }

        let size = Int(openedInfo.st_size)
        var data = Data(count: size)
        let bytesRead = data.withUnsafeMutableBytes { bytes -> Int in
            guard let baseAddress = bytes.baseAddress else { return size == 0 ? 0 : -1 }
            return Darwin.read(descriptor, baseAddress, size)
        }
        guard bytesRead == size else { return nil }

        var finalInfo = stat()
        var pathInfo = stat()
        guard fstat(descriptor, &finalInfo) == 0,
              lstat(url.path, &pathInfo) == 0,
              sameFile(openedInfo, finalInfo),
              sameFile(finalInfo, pathInfo),
              isType(pathInfo.st_mode, S_IFREG) else { return nil }

        guard let decoded = try? JSONDecoder().decode(TaskLease.self, from: data),
              isValid(decoded, nowMilliseconds: nowMilliseconds) else { return nil }
        return decoded
    }

    private func isValid(_ lease: TaskLease, nowMilliseconds: Double) -> Bool {
        guard lease.version == 1,
              lease.provider == "codex" || lease.provider == "claude-code",
              (1...256).contains(lease.sessionId.utf8.count),
              lease.turnId.map({ $0.utf8.count <= 256 }) ?? true,
              lease.timestamp.isFinite,
              lease.timestamp >= 0,
              lease.timestamp <= nowMilliseconds + 60_000 else { return false }

        if let title = lease.title {
            guard title.count <= 120,
                  title.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return false }
        }
        if let startedAt = lease.startedAt {
            guard startedAt.isFinite, startedAt >= 0, startedAt <= lease.timestamp else { return false }
        }

        let maximumAge: Double
        switch lease.event {
        case .started: maximumAge = Self.startedMaximumAgeMilliseconds
        case .running: maximumAge = Self.runningMaximumAgeMilliseconds
        case .needsInput: maximumAge = Self.waitingMaximumAgeMilliseconds
        case .ended, .completed, .failed: maximumAge = Self.terminalMaximumAgeMilliseconds
        }
        return nowMilliseconds - lease.timestamp <= maximumAge
    }

    private func metadata(atPath path: String) throws -> stat {
        var info = stat()
        let result = Darwin.lstat(path, &info)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return info
    }

    private func sameFile(_ left: stat, _ right: stat) -> Bool {
        left.st_dev == right.st_dev
            && left.st_ino == right.st_ino
            && left.st_size == right.st_size
            && left.st_mtimespec.tv_sec == right.st_mtimespec.tv_sec
            && left.st_mtimespec.tv_nsec == right.st_mtimespec.tv_nsec
    }

    private func isType(_ mode: mode_t, _ type: mode_t) -> Bool {
        mode & S_IFMT == type
    }

    private func isLeaseName(_ name: String) -> Bool {
        guard name.count == 69, name.hasSuffix(".json") else { return false }
        return name.dropLast(5).allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}
