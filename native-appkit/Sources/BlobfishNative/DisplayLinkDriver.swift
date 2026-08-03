import CoreVideo
import Foundation

final class DisplayLinkDriver {
    typealias FrameHandler = (TimeInterval) -> Void

    private let handler: FrameHandler
    private let stateLock = NSLock()
    private var displayLink: CVDisplayLink?
    private var mainFrameQueued = false

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
            let driver = Unmanaged<DisplayLinkDriver>.fromOpaque(context).takeUnretainedValue()
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
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            self.mainFrameQueued = false
            self.stateLock.unlock()
            guard self.isRunning else { return }
            self.handler(ProcessInfo.processInfo.systemUptime)
        }
    }
}
