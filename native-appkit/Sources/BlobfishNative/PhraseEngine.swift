import Foundation

final class PhraseEngine {
    private let phrases: [Phrase]
    private let now: () -> Double
    private let random: () -> Double
    private let historyLimit: Int
    private var history: [String] = []
    private var lastUsedAt: [String: Double] = [:]

    init(
        phrases: [Phrase],
        historyLimit: Int = 20,
        now: @escaping () -> Double = { Date().timeIntervalSince1970 * 1_000 },
        random: @escaping () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.phrases = phrases
        self.historyLimit = historyLimit
        self.now = now
        self.random = random
    }

    func select(event: String, context: [String: JSONValue] = [:]) -> Phrase? {
        let timestamp = now()
        let candidates = phrases.compactMap { phrase -> (Phrase, Double)? in
            guard phrase.event == event,
                  Self.matches(phrase.conditions ?? [:], context: context),
                  let rendered = Self.render(phrase.text, context: context) else { return nil }
            if let previous = lastUsedAt[phrase.id], timestamp - previous < (phrase.cooldownMs ?? 0) { return nil }
            let rarity: Double
            switch phrase.rarity ?? "common" {
            case "uncommon": rarity = 0.35
            case "rare": rarity = 0.06
            default: rarity = 1
            }
            return (Phrase(
                id: phrase.id, event: phrase.event, text: rendered, weight: phrase.weight,
                rarity: phrase.rarity, cooldownMs: phrase.cooldownMs, conditions: phrase.conditions
            ), max(0, phrase.weight ?? 1) * rarity)
        }
        guard !candidates.isEmpty else { return nil }
        let unseen = candidates.filter { !history.contains($0.0.id) }
        let pool = unseen.isEmpty ? candidates : unseen
        let total = pool.reduce(0) { $0 + $1.1 }
        var cursor = min(max(random(), 0), 0.999_999_999) * total
        var selected = pool.last!.0
        for candidate in pool {
            cursor -= candidate.1
            if cursor < 0 { selected = candidate.0; break }
        }
        lastUsedAt[selected.id] = timestamp
        history.append(selected.id)
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
        return selected
    }

    private static func render(_ text: String, context: [String: JSONValue]) -> String? {
        let pattern = try! NSRegularExpression(pattern: #"\{([A-Za-z][A-Za-z0-9]*)\}"#)
        let range = NSRange(text.startIndex..., in: text)
        var rendered = text
        for match in pattern.matches(in: text, range: range).reversed() {
            guard let keyRange = Range(match.range(at: 1), in: text),
                  let wholeRange = Range(match.range(at: 0), in: rendered),
                  let value = context[String(text[keyRange])],
                  let scalar = scalarString(value) else { return nil }
            rendered.replaceSubrange(wholeRange, with: scalar)
        }
        return rendered
    }

    private static func scalarString(_ value: JSONValue) -> String? {
        switch value {
        case .string(let value): return value
        case .number(let value): return value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): return String(value)
        default: return nil
        }
    }

    private static func matches(_ conditions: [String: JSONValue], context: [String: JSONValue]) -> Bool {
        for (key, condition) in conditions {
            switch key {
            case "requires":
                guard let keys = condition.arrayValue?.compactMap(\.stringValue),
                      keys.count == condition.arrayValue?.count,
                      keys.allSatisfy({ context[$0] != nil }) else { return false }
            case "batteryEquals": guard numbersEqual(context["battery"], condition) else { return false }
            case "activeCountMin": guard number(context["activeCount"]) >= number(condition) else { return false }
            case "remainingMin": guard number(context["remaining"]) >= number(condition) else { return false }
            case "remainingEquals": guard numbersEqual(context["remaining"], condition) else { return false }
            case "durationMinSeconds": guard number(context["durationSeconds"]) >= number(condition) else { return false }
            case "lockedMinSeconds": guard number(context["lockedSeconds"]) >= number(condition) else { return false }
            case "clickCountMin": guard number(context["clickCount"]) >= number(condition) else { return false }
            case "provider": guard context["provider"]?.stringValue == condition.stringValue else { return false }
            case "weekdays":
                guard let weekday = context["weekday"]?.numberValue,
                      condition.arrayValue?.contains(where: { $0.numberValue == weekday }) == true else { return false }
            case "hourMin": guard number(context["hour"]) >= number(condition) else { return false }
            case "hourMax": guard number(context["hour"]) <= number(condition) else { return false }
            default: return false
            }
        }
        return true
    }

    private static func number(_ value: JSONValue?) -> Double {
        value?.numberValue ?? -.infinity
    }

    private static func numbersEqual(_ left: JSONValue?, _ right: JSONValue?) -> Bool {
        guard let lhs = left?.numberValue, let rhs = right?.numberValue else { return false }
        return lhs == rhs
    }
}
