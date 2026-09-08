import Foundation

// Prepare in the normal run loop, never inside AppKit's terminateLater loop.
final class AppTerminationGate {
    enum Decision { case terminateNow, prepare, wait }
    private enum State { case idle, preparing, ready }
    private var state = State.idle

    func request(needsCleanup: Bool) -> Decision {
        switch state {
        case .ready: return .terminateNow
        case .preparing: return .wait
        case .idle:
            state = needsCleanup ? .preparing : .ready
            return needsCleanup ? .prepare : .terminateNow
        }
    }

    // Cleanup completion and the independent deadline may race; only one wins.
    func finish() -> Bool {
        guard state == .preparing else { return false }
        state = .ready
        return true
    }
}
