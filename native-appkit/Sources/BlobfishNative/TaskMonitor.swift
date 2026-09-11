import Foundation

enum TaskMonitorPollingPolicy {
    static func snapshot(
        enabledProviders: Set<String>,
        includeTitles: Bool,
        nowMilliseconds: Double,
        readLeases: () throws -> [TaskLease]
    ) throws -> TaskSnapshot {
        guard !enabledProviders.isEmpty else { return .idle }
        let leases = try readLeases().filter { enabledProviders.contains($0.provider) }
        return TaskSnapshot.build(
            from: leases,
            nowMilliseconds: nowMilliseconds,
            includeTitles: includeTitles
        )
    }
}

struct TaskSnapshotDeduplicator {
    private var previous: TaskSnapshot?

    mutating func reset() { previous = nil }

    mutating func shouldDeliver(_ snapshot: TaskSnapshot) -> Bool {
        guard previous != snapshot else { return false }
        previous = snapshot
        return true
    }
}

final class TaskMonitor {
    var onUpdate: ((TaskSnapshot) -> Void)?
    var onCodexUpdate: (([CodexObservedThread]) -> Void)?
    var showQuestions = false
    var includeTitles = true
    var enabledProviders = Set(["codex", "claude-code"])

    private let reader: TaskLeaseReader
    private let observationDirectory: URL
    private let queue = DispatchQueue(label: "com.blobfish.native.task-monitor", qos: .utility)
    private var timer: Timer?
    private var polling = false
    private var isRunning = false
    private var runGeneration = 0
    private var deduplicator = TaskSnapshotDeduplicator()
    private var lastLoggedError: String?

    init(directoryURL: URL) {
        reader = TaskLeaseReader(directoryURL: directoryURL)
        observationDirectory = directoryURL.deletingLastPathComponent().appendingPathComponent("codex-observations")
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        runGeneration += 1
        deduplicator.reset()
        lastLoggedError = nil
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
        let shouldShowQuestions = showQuestions
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date().timeIntervalSince1970 * 1_000
            let snapshot: TaskSnapshot
            let errorDescription: String?
            var observations: [CodexObservedThread] = []
            do {
                snapshot = try TaskMonitorPollingPolicy.snapshot(
                    enabledProviders: providers,
                    includeTitles: shouldIncludeTitles,
                    nowMilliseconds: now,
                    readLeases: {
                        let observed = providers.contains("codex") ? CodexObservationFiles.load(directory: self.observationDirectory, now: now) : []
                        observations = observed.map { value in
                            var value = value
                            if !shouldShowQuestions { value.questions = [] }
                            return value
                        }
                        return CodexTaskProjection.merge(
                            leases: try self.reader.read(nowMilliseconds: now), observations: observed, now: now
                        )
                    }
                )
                errorDescription = nil
            } catch {
                snapshot = TaskSnapshot.build(
                    from: CodexTaskProjection.merge(leases: [], observations: observations, now: now),
                    nowMilliseconds: now, includeTitles: shouldIncludeTitles
                )
                errorDescription = String(describing: error)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning, self.runGeneration == generation else { return }
                self.polling = false
                guard providers == self.enabledProviders, shouldIncludeTitles == self.includeTitles,
                      shouldShowQuestions == self.showQuestions else {
                    self.poll()
                    return
                }
                self.onCodexUpdate?(observations)
                if errorDescription != self.lastLoggedError {
                    self.lastLoggedError = errorDescription
                    if let errorDescription {
                        NSLog(
                            "Native task monitor skipped an unsafe or unreadable lease directory: %@",
                            errorDescription
                        )
                    }
                }
                guard self.deduplicator.shouldDeliver(snapshot) else { return }
                self.onUpdate?(snapshot)
            }
        }
    }
}
