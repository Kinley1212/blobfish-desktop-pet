import Foundation

enum CodexAttentionPolicy {
    static func blockingIDs(_ observations: [CodexObservedThread]) -> Set<String> {
        Set(observations.flatMap { thread in thread.blockingQuestions.map { "\(thread.id)|\(thread.turnID)|\($0)" } })
    }

    static func unpreviewedBlockingIDs(_ observations: [CodexObservedThread], previews: [CodexQuestionRequest], previous: Set<String>) -> Set<String> {
        let visible = Set(previews.filter(\.blocking).map { "\($0.threadID)|\($0.turnID)|\($0.id)" })
        return blockingIDs(observations).subtracting(previous).subtracting(visible)
    }
}

enum CodexTaskProjection {
    static func merge(leases: [TaskLease], observations: [CodexObservedThread], now: Double) -> [TaskLease] {
        let observedIDs = Set(observations.map(\.id))
        let fallback = leases.filter { $0.provider != "codex" || !observedIDs.contains($0.sessionId) }
        return fallback + observations.compactMap { thread -> TaskLease? in
            guard thread.state != "interrupted" else { return nil }
            let previous = leases.first { $0.provider == "codex" && $0.sessionId == thread.id && $0.turnId == thread.turnID }
            let event: LeaseEvent = thread.state == "failed" ? .failed : thread.state == "ended" ? .ended
                : (!thread.approvals.isEmpty || !thread.blockingQuestions.isEmpty) ? .needsInput : .running
            return TaskLease(version: 1, provider: "codex", event: event, sessionId: thread.id,
                             turnId: thread.turnID, title: previous?.title, timestamp: thread.timestamp,
                             startedAt: previous?.startedAt)
        }
    }
}
