import Foundation

struct SpeechMessage: Equatable {
    let text: String
    let event: String?
    let priority: Int
    let duration: TimeInterval
    let replaceKey: String?
    fileprivate let sequence: Int
}

final class SpeechQueue {
    private let deliver: (SpeechMessage) -> Void
    private let onIdle: () -> Void
    private(set) var current: SpeechMessage?
    private(set) var pending: [SpeechMessage] = []
    private var timer: Timer?
    private var sequence = 0

    init(deliver: @escaping (SpeechMessage) -> Void, onIdle: @escaping () -> Void) {
        self.deliver = deliver
        self.onIdle = onIdle
    }

    @discardableResult
    func enqueue(
        text: String,
        event: String?,
        priority: Int,
        duration: TimeInterval,
        replaceKey: String?
    ) -> Bool {
        guard !text.isEmpty else { return false }
        let entry = SpeechMessage(
            text: text,
            event: event,
            priority: priority,
            duration: duration,
            replaceKey: replaceKey,
            sequence: sequence
        )
        sequence += 1

        if let replaceKey {
            pending.removeAll { $0.replaceKey == replaceKey }
        }
        guard let current else {
            start(entry)
            return true
        }
        if let replaceKey, replaceKey == current.replaceKey {
            cancelCurrent()
            start(entry)
        } else if entry.priority > current.priority {
            cancelCurrent()
            start(entry)
        } else {
            pending.append(entry)
            pending.sort { left, right in
                left.priority == right.priority
                    ? left.sequence < right.sequence
                    : left.priority > right.priority
            }
        }
        return true
    }

    func clear() {
        timer?.invalidate()
        timer = nil
        current = nil
        pending.removeAll()
        onIdle()
    }

    func finishCurrent() {
        timer?.invalidate()
        timer = nil
        current = nil
        if pending.isEmpty {
            onIdle()
        } else {
            start(pending.removeFirst())
        }
    }

    private func cancelCurrent() {
        timer?.invalidate()
        timer = nil
        current = nil
    }

    private func start(_ entry: SpeechMessage) {
        current = entry
        deliver(entry)
        timer = Timer.scheduledTimer(withTimeInterval: entry.duration, repeats: false) { [weak self] _ in
            self?.finishCurrent()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
}
