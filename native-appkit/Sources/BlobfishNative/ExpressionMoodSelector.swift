import Foundation

enum ExpressionMoodSelector {
    private struct Rule {
        let prefix: String
        let chance: Double
        let faces: [String]
    }

    private static let rules = [
        Rule(prefix: "interaction.click", chance: 0.5, faces: ["face-cry", "face-panic", "face-shocked", "face-angry", "face-scared", "face-pitiful"]),
        Rule(prefix: "interaction.pettingLots", chance: 0.5, faces: ["face-love", "face-coy", "face-sparkle", "face-nosebleed", "face-swirl-cheek"]),
        Rule(prefix: "interaction.pettingMore", chance: 0.5, faces: ["face-coy", "face-happy", "face-smug", "face-shy", "face-satisfied"]),
        Rule(prefix: "interaction.petting", chance: 0.5, faces: ["face-coy", "face-smug", "face-blank", "face-shy", "face-side-eye"]),
        Rule(prefix: "interaction.goodbye", chance: 0.6, faces: ["face-wink", "face-relieved", "face-satisfied"]),
        Rule(prefix: "interaction.", chance: 0.3, faces: ["face-blank", "face-smug", "face-happy", "face-side-eye", "face-teasing"]),
        Rule(prefix: "idle.lateNight", chance: 0.6, faces: ["face-sleepy", "face-dizzy", "face-blank", "face-cold"]),
        Rule(prefix: "idle.longSession", chance: 0.6, faces: ["face-dizzy", "face-annoyed", "face-sleepy", "face-cold"]),
        Rule(prefix: "idle.weekend", chance: 0.45, faces: ["face-relieved", "face-happy", "face-smug", "face-satisfied", "face-swirl-cheek"]),
        Rule(prefix: "idle.", chance: 0.3, faces: ["face-blank", "face-sleepy", "face-smug", "face-annoyed", "face-side-eye", "face-cold", "face-question"]),
        Rule(prefix: "schedule.lunchSoon", chance: 0.8, faces: ["face-hungry", "face-sparkle", "face-happy", "face-satisfied"]),
        Rule(prefix: "schedule.offWork", chance: 0.7, faces: ["face-relieved", "face-sparkle", "face-happy", "face-satisfied", "face-teasing"]),
        Rule(prefix: "schedule.halfHour", chance: 0.4, faces: ["face-annoyed", "face-blank", "face-sleepy", "face-cold", "face-side-eye"]),
        Rule(prefix: "schedule.", chance: 0.4, faces: ["face-blank", "face-happy"]),
        Rule(prefix: "agent.failed", chance: 0.9, faces: ["face-panic", "face-shocked", "face-pitiful", "face-scared"]),
        Rule(prefix: "agent.needsInput", chance: 0.7, faces: ["face-pitiful", "face-shocked", "face-coy", "face-question", "face-doubt"]),
        Rule(prefix: "agent.allCompleted", chance: 0.85, faces: ["face-proud", "face-sparkle", "face-relieved", "face-satisfied", "face-star-eye"]),
        Rule(prefix: "agent.completed", chance: 0.6, faces: ["face-happy", "face-proud", "face-sparkle", "face-satisfied"]),
        Rule(prefix: "agent.longRunning", chance: 0.5, faces: ["face-sleepy", "face-annoyed", "face-dizzy", "face-cold"]),
        Rule(prefix: "agent.started", chance: 0.4, faces: ["face-determined", "face-sparkle", "face-blank"]),
        Rule(prefix: "agent.", chance: 0.3, faces: ["face-blank", "face-happy", "face-smug", "face-determined"]),
        Rule(prefix: "system.error", chance: 0.95, faces: ["face-panic", "face-shocked", "face-dizzy", "face-scared"]),
        Rule(prefix: "system.battery", chance: 0.7, faces: ["face-panic", "face-pitiful", "face-dizzy", "face-scared"]),
        Rule(prefix: "system.unlocked", chance: 0.5, faces: ["face-happy", "face-sparkle", "face-sleepy", "face-shy"]),
        Rule(prefix: "system.", chance: 0.35, faces: ["face-blank", "face-happy", "face-question"]),
        Rule(prefix: "calendar.busyDay", chance: 0.6, faces: ["face-dizzy", "face-panic", "face-annoyed", "face-scared", "face-cold"]),
        Rule(prefix: "calendar.freeGap", chance: 0.5, faces: ["face-relieved", "face-happy", "face-satisfied", "face-swirl-cheek"]),
        Rule(prefix: "calendar.", chance: 0.4, faces: ["face-shocked", "face-blank", "face-panic", "face-doubt"]),
        Rule(prefix: "startup.", chance: 0.6, faces: ["face-happy", "face-sleepy", "face-sparkle", "face-shy", "face-satisfied"]),
        Rule(prefix: "rare.", chance: 0.9, faces: ["face-sparkle", "face-love", "face-proud", "face-dizzy", "face-wink", "face-star-eye", "face-money", "face-teasing", "face-nosebleed"]),
    ]

    static func pick(
        event: String,
        available: Set<String>,
        random: () -> Double = { Double.random(in: 0..<1) }
    ) -> String? {
        guard let rule = rules.first(where: { event.hasPrefix($0.prefix) }), random() < rule.chance else { return nil }
        let candidates = rule.faces.filter(available.contains)
        guard !candidates.isEmpty else { return nil }
        let value = min(0.999_999, max(0, random()))
        return candidates[min(candidates.count - 1, Int(value * Double(candidates.count)))]
    }
}
