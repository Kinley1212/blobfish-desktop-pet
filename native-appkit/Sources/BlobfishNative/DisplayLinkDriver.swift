import CoreVideo
import Foundation

final class DisplayLinkDriver {
    typealias FrameHandler = (TimeInterval) -> Void

    private let handler: FrameHandler
    private var token: UUID?
    var isRunning: Bool { token != nil }

    init(handler: @escaping FrameHandler) { self.handler = handler }
    deinit { stop() }

    func start() {
        guard token == nil else { return }
        token = SharedDisplayFrames.shared.add { [weak self] uptime in self?.handler(uptime) }
    }

    func stop() {
        guard let token else { return }
        self.token = nil
        SharedDisplayFrames.shared.remove(token)
    }
}

// Main-thread subscribers share one hardware clock and one queued main callback.
// Tokens prevent a stopped/restarted subscriber receiving a stale frame.
final class FrameSubscribers {
    private var handlers: [UUID: (TimeInterval) -> Void] = [:]
    private var order: [UUID] = []
    var isEmpty: Bool { handlers.isEmpty }

    func add(_ handler: @escaping (TimeInterval) -> Void) -> UUID {
        let token = UUID()
        handlers[token] = handler
        order.append(token)
        return token
    }

    func remove(_ token: UUID) {
        handlers[token] = nil
        order.removeAll { $0 == token }
    }

    func deliver(_ uptime: TimeInterval) {
        let current = order
        for token in current { handlers[token]?(uptime) }
    }
}

private final class SharedDisplayFrames {
    static let shared = SharedDisplayFrames()
    private let subscribers = FrameSubscribers()
    private lazy var source = DisplayLinkSource { [weak self] uptime in
        self?.subscribers.deliver(uptime)
    }

    func add(_ handler: @escaping (TimeInterval) -> Void) -> UUID? {
        source.start()
        guard source.isRunning else { return nil }
        return subscribers.add(handler)
    }

    func remove(_ token: UUID) {
        subscribers.remove(token)
        if subscribers.isEmpty { source.stop() }
    }
}

private final class DisplayLinkSource {
    typealias FrameHandler = (TimeInterval) -> Void

    private let handler: FrameHandler
    private let stateLock = NSLock()
    private var displayLink: CVDisplayLink?
    private var mainFrameQueued = false
    private var generation = 0

    private(set) var isRunning = false

    init(handler: @escaping FrameHandler) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        guard !isRunning else { return }
        var created: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&created) == kCVReturnSuccess,
              let created else { return }
        CVDisplayLinkSetOutputCallback(created, { _, _, _, _, _, context in
            guard let context else { return kCVReturnInvalidArgument }
            let driver = Unmanaged<DisplayLinkSource>.fromOpaque(context).takeUnretainedValue()
            driver.enqueueMainFrame()
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())
        displayLink = created
        isRunning = CVDisplayLinkStart(created) == kCVReturnSuccess
        if !isRunning { displayLink = nil }
    }

    func stop() {
        if let displayLink, CVDisplayLinkIsRunning(displayLink) {
            CVDisplayLinkStop(displayLink)
        }
        displayLink = nil
        isRunning = false
        stateLock.lock()
        generation += 1
        mainFrameQueued = false
        stateLock.unlock()
    }

    private func enqueueMainFrame() {
        stateLock.lock()
        guard !mainFrameQueued else {
            stateLock.unlock()
            return
        }
        mainFrameQueued = true
        let queuedGeneration = generation
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            guard self.generation == queuedGeneration else {
                self.stateLock.unlock()
                return
            }
            self.mainFrameQueued = false
            self.stateLock.unlock()
            guard self.isRunning else { return }
            self.handler(ProcessInfo.processInfo.systemUptime)
        }
    }
}
