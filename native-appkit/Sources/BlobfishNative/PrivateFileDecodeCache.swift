import Darwin
import Foundation

// Owned by the task monitor's serial queue. Cache decoded values, never skip
// current permission checks or the caller's time-dependent validation.
final class PrivateFileDecodeCache<Value> {
    private struct Fingerprint: Equatable {
        let device: dev_t
        let inode: ino_t
        let bytes: off_t
        let modifiedSeconds: Int
        let modifiedNanos: Int
        let changedSeconds: Int
        let changedNanos: Int

        init?(_ url: URL, maximumBytes: Int) {
            var info = stat()
            guard lstat(url.path, &info) == 0,
                  info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
                  info.st_mode & 0o077 == 0, info.st_mode & S_IRUSR != 0, info.st_size >= 0,
                  info.st_size <= maximumBytes else { return nil }
            device = info.st_dev; inode = info.st_ino; bytes = info.st_size
            modifiedSeconds = info.st_mtimespec.tv_sec; modifiedNanos = info.st_mtimespec.tv_nsec
            changedSeconds = info.st_ctimespec.tv_sec; changedNanos = info.st_ctimespec.tv_nsec
        }
    }
    private struct Entry {
        let fingerprint: Fingerprint
        let value: Value
    }
    private var entries: [URL: Entry] = [:]
    private let maximumEntries: Int
    private let maximumSourceBytes: Int
    private(set) var sourceBytes = 0
    var count: Int { entries.count }

    init(maximumEntries: Int, maximumSourceBytes: Int) {
        self.maximumEntries = maximumEntries
        self.maximumSourceBytes = maximumSourceBytes
    }

    func removeAll() { entries.removeAll(); sourceBytes = 0 }

    func retainOnly(_ urls: Set<URL>) {
        for url in Array(entries.keys) where !urls.contains(url) { remove(url) }
    }

    private func remove(_ url: URL) {
        if let old = entries.removeValue(forKey: url) { sourceBytes -= Int(old.fingerprint.bytes) }
    }

    func load(_ url: URL, maximumFileBytes: Int, read: () throws -> Value?) rethrows -> Value? {
        guard let before = Fingerprint(url, maximumBytes: maximumFileBytes) else {
            remove(url)
            return nil
        }
        if let cached = entries[url], cached.fingerprint == before,
           Fingerprint(url, maximumBytes: maximumFileBytes) == before {
            return cached.value
        }
        remove(url)
        guard let value = try read(), Fingerprint(url, maximumBytes: maximumFileBytes) == before else { return nil }
        let cost = Int(before.bytes)
        // Source-byte budget bounds retained inputs, not an RSS measurement.
        // Oversized entries are still read normally, simply not retained.
        if entries.count < maximumEntries, cost <= maximumSourceBytes - sourceBytes {
            entries[url] = Entry(fingerprint: before, value: value)
            sourceBytes += cost
        }
        return value
    }
}
