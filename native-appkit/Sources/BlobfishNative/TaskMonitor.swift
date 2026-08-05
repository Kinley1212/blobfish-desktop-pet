import Foundation

final class TaskMonitor {
    var onUpdate: ((TaskSnapshot) -> Void)?
    var includeTitles = true
    var enabledProviders = Set(["codex", "claude-code"])

    private let reader: TaskLeaseReader
    private let queue = DispatchQueue(label: "com.blobfish.native.task-monitor", qos: .utility)
    private var timer: Timer?
    private var polling = false
    private var isRunning = false
    private var runGeneration = 0

    init(directoryURL: URL) {
        reader = TaskLeaseReader(directoryURL: directoryURL)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        runGeneration += 1
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.poll()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        isRunning = false
        runGeneration += 1
        timer?.invalidate()
        timer = nil
        polling = false
    }

    private func poll() {
        guard isRunning, !polling else { return }
        polling = true
        let generation = runGeneration
        let providers = enabledProviders
        let shouldIncludeTitles = includeTitles
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date().timeIntervalSince1970 * 1_000
            let snapshot: TaskSnapshot
            do {
                let leases = try self.reader.read(nowMilliseconds: now).filter { providers.contains($0.provider) }
                snapshot = TaskSnapshot.build(
                    from: leases,
                    nowMilliseconds: now,
                    includeTitles: shouldIncludeTitles
                )
            } catch {
                snapshot = .idle
                NSLog("Native task monitor skipped an unsafe or unreadable lease directory: %@", String(describing: error))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning, self.runGeneration == generation else { return }
                self.polling = false
                self.onUpdate?(snapshot)
            }
        }
    }
}
