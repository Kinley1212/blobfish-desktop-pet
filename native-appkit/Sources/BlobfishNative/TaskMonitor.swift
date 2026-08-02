import Foundation

final class TaskMonitor {
    var onUpdate: ((TaskSnapshot) -> Void)?

    private let reader: TaskLeaseReader
    private let queue = DispatchQueue(label: "com.blobfish.native.task-monitor", qos: .utility)
    private var timer: Timer?
    private var polling = false

    init(directoryURL: URL) {
        reader = TaskLeaseReader(directoryURL: directoryURL)
    }

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard !polling else { return }
        polling = true
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date().timeIntervalSince1970 * 1_000
            let snapshot: TaskSnapshot
            do {
                snapshot = TaskSnapshot.build(from: try self.reader.read(nowMilliseconds: now), nowMilliseconds: now)
            } catch {
                snapshot = .idle
                NSLog("Native task monitor skipped an unsafe or unreadable lease directory: %@", String(describing: error))
            }
            DispatchQueue.main.async { [weak self] in
                self?.polling = false
                self?.onUpdate?(snapshot)
            }
        }
    }
}
