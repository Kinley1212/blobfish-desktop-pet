import EventKit
import Foundation

final class CalendarService {
    var onPhrase: ((String, [String: JSONValue]) -> Void)?
    var onStatus: ((String) -> Void)?

    private let runtime: AppRuntime
    private let store = EKEventStore()
    private var timer: Timer?
    private var delivered = BoundedKeyHistory(limit: 512)
    private var isRunning = false
    private var runGeneration = 0

    init(runtime: AppRuntime) { self.runtime = runtime }

    func start() {
        guard !isRunning else { return }
        guard runtime.config.integrations.calendar else { onStatus?("disabled"); return }
        isRunning = true
        runGeneration += 1
        let generation = runGeneration
        requestAccess { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.isRunning, self.runGeneration == generation else { return }
                guard granted else {
                    self.isRunning = false
                    self.onStatus?("denied")
                    return
                }
                self.onStatus?("connected")
                self.poll()
                self.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.poll() }
                if let timer = self.timer { RunLoop.main.add(timer, forMode: .common) }
            }
        }
    }

    func stop() {
        isRunning = false
        runGeneration += 1
        timer?.invalidate()
        timer = nil
    }

    private func requestAccess(completion: @escaping (Bool) -> Void) {
        // requestAccess(to:) remains available on the Intel/macOS 13 SDK used
        // by the local test machine and still prompts correctly on newer macOS.
        store.requestAccess(to: .event) { granted, _ in completion(granted) }
    }

    private func poll() {
        guard isRunning else { return }
        let now = Date(), end = now.addingTimeInterval(24 * 60 * 60)
        let events = store.events(matching: store.predicateForEvents(withStart: now.addingTimeInterval(-60), end: end, calendars: nil))
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
        let dayKey = Self.dayFormatter.string(from: now)
        if events.count >= 6 { emitOnce(key: "busy:\(dayKey)", event: "calendar.busyDay", context: ["count": .number(Double(events.count))]) }
        for event in events.prefix(20) {
            let minutes = Int(event.startDate.timeIntervalSince(now) / 60)
            var context: [String: JSONValue] = ["minutes": .number(Double(max(0, minutes)))]
            if runtime.config.privacy.includeCalendarTitles, let title = event.title, !title.isEmpty { context["title"] = .string(title) }
            let id = event.eventIdentifier ?? "\(event.startDate.timeIntervalSince1970)-\(event.title ?? "")"
            if (-1...1).contains(minutes) {
                emitOnce(key: "start:\(id)", event: "calendar.starting", context: context)
            } else if (2...15).contains(minutes) {
                emitOnce(key: "soon:\(id)", event: "calendar.upcoming", context: context)
            }
        }
    }

    private func emitOnce(key: String, event: String, context: [String: JSONValue]) {
        guard delivered.insert(key) else { return }
        onPhrase?(event, context)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }()
}
