import Foundation

struct PetAnimationTimeline {
    let startedAt: TimeInterval
    let duration: TimeInterval

    init(duration: TimeInterval, startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.duration = duration
        self.startedAt = startedAt
    }

    func progress(at uptime: TimeInterval) -> CGFloat {
        CGFloat(min(1, max(0, (uptime - startedAt) / duration)))
    }
}
