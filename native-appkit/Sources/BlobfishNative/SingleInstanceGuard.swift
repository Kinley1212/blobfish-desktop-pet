import Darwin
import Foundation

final class SingleInstanceGuard {
    private static let registryLock = NSLock()
    private static var acquiredPaths = Set<String>()

    private var descriptor: Int32 = -1
    private var acquiredPath: String?

    func acquire(in directory: URL) -> Bool {
        guard descriptor < 0 else { return true }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch { return false }
        let file = directory.appendingPathComponent("native-instance.lock").standardizedFileURL
        let path = file.path
        Self.registryLock.lock()
        let reserved = Self.acquiredPaths.insert(path).inserted
        Self.registryLock.unlock()
        guard reserved else { return false }

        let opened = Darwin.open(file.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard opened >= 0 else {
            releaseRegistryPath(path)
            return false
        }
        var info = stat()
        var lock = flock()
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)
        guard fstat(opened, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              fcntl(opened, F_SETLK, &lock) == 0 else {
            Darwin.close(opened)
            releaseRegistryPath(path)
            return false
        }
        descriptor = opened
        acquiredPath = path
        return true
    }

    deinit {
        if descriptor >= 0 { Darwin.close(descriptor) }
        if let acquiredPath { releaseRegistryPath(acquiredPath) }
    }

    private func releaseRegistryPath(_ path: String) {
        Self.registryLock.lock()
        Self.acquiredPaths.remove(path)
        Self.registryLock.unlock()
    }
}
