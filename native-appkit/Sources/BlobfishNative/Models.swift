import Foundation

enum LeaseEvent: String, Decodable {
    case started
    case running
    case needsInput = "needs_input"
    case ended
    case completed
    case failed

    var isActive: Bool {
        self == .started || self == .running || self == .needsInput
    }
}

struct TaskLease: Decodable, Equatable {
    let version: Int
    let provider: String
    let event: LeaseEvent
    let sessionId: String
    let turnId: String?
    let title: String?
    let timestamp: Double
    let startedAt: Double?
}

enum TaskDisplayState: Equatable {
    case idle
    case running
    case waiting
    case completed
    case failed
}

struct TaskSnapshot: Equatable {
    let state: TaskDisplayState
    let title: String?
    let activeCount: Int
    let tasks: [TaskCard]

    static let idle = TaskSnapshot(state: .idle, title: nil, activeCount: 0, tasks: [])

    static func build(from leases: [TaskLease], nowMilliseconds: Double, includeTitles: Bool = true) -> TaskSnapshot {
        let active = leases.filter { $0.event.isActive }
        if !active.isEmpty {
            let newest = active.max { $0.timestamp < $1.timestamp }
            let allWaiting = active.allSatisfy { $0.event == .needsInput }
            let cards = active.sorted { $0.timestamp > $1.timestamp }.map {
                TaskCard(
                    id: $0.sessionId,
                    provider: $0.provider,
                    state: $0.event == .needsInput ? .waiting : .running,
                    title: displayTitle($0, includeTitles: includeTitles),
                    timestamp: $0.timestamp
                )
            }
            return TaskSnapshot(
                state: allWaiting ? .waiting : .running,
                title: newest.map { displayTitle($0, includeTitles: includeTitles) },
                activeCount: active.count,
                tasks: cards
            )
        }

        guard let terminal = leases
            .filter({ !$0.event.isActive && nowMilliseconds - $0.timestamp <= 5_000 })
            .max(by: { $0.timestamp < $1.timestamp }) else {
            return .idle
        }
        return TaskSnapshot(
            state: terminal.event == .failed ? .failed : .completed,
            title: displayTitle(terminal, includeTitles: includeTitles),
            activeCount: 0,
            tasks: [TaskCard(
                id: terminal.sessionId,
                provider: terminal.provider,
                state: terminal.event == .failed ? .failed : .completed,
                title: displayTitle(terminal, includeTitles: includeTitles),
                timestamp: terminal.timestamp
            )]
        )
    }

    private static func displayTitle(_ lease: TaskLease, includeTitles: Bool) -> String {
        if includeTitles, let title = lease.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return lease.provider == "claude-code" ? "Claude Code 任务" : "Codex 任务"
    }
}

struct TaskCard: Equatable, Identifiable {
    let id: String
    let provider: String
    let state: TaskDisplayState
    let title: String
    let timestamp: Double
}
