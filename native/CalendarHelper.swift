import EventKit
import Foundation

private struct EventRecord: Encodable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
}

private struct HelperOutput: Encodable {
    let status: String
    let events: [EventRecord]
    let error: String?
}

private final class AccessResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedGranted = false
    private var storedError: String?

    func set(granted: Bool, error: Error?) {
        lock.lock()
        storedGranted = granted
        storedError = error?.localizedDescription
        lock.unlock()
    }

    func get() -> (Bool, String?) {
        lock.lock()
        defer { lock.unlock() }
        return (storedGranted, storedError)
    }
}

@main
private struct CalendarHelper {
    static func authorizationName(_ status: EKAuthorizationStatus) -> String {
        if status == .notDetermined { return "notDetermined" }
        if status == .restricted { return "restricted" }
        if status == .denied { return "denied" }
        if #available(macOS 14.0, *) {
            if status == .fullAccess { return "authorized" }
            if status == .writeOnly { return "writeOnly" }
        }
        if status == .authorized { return "authorized" }
        return "unknown"
    }

    static func requestAccess(_ store: EKEventStore) -> (Bool, String?) {
        let semaphore = DispatchSemaphore(value: 0)
        let result = AccessResult()
        let completion: EKEventStoreRequestAccessCompletionHandler = { granted, error in
            result.set(granted: granted, error: error)
            semaphore.signal()
        }

        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: completion)
        } else {
            store.requestAccess(to: .event, completion: completion)
        }
        semaphore.wait()
        return result.get()
    }

    static func emit(_ output: HelperOutput, exitCode: Int32 = 0) -> Never {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(output)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("Unable to encode calendar helper output\n".utf8))
        }
        Foundation.exit(exitCode)
    }

    static func main() {
        let arguments = CommandLine.arguments
        let shouldRequestAccess = arguments.contains("--request-access")
        var horizonMinutes = 24 * 60
        if let index = arguments.firstIndex(of: "--minutes"), arguments.indices.contains(index + 1),
           let value = Int(arguments[index + 1]) {
            horizonMinutes = min(max(value, 1), 7 * 24 * 60)
        }

        let store = EKEventStore()
        if shouldRequestAccess {
            let (granted, error) = requestAccess(store)
            if !granted {
                let status = authorizationName(EKEventStore.authorizationStatus(for: .event))
                emit(HelperOutput(status: status, events: [], error: error))
            }
        }

        let status = authorizationName(EKEventStore.authorizationStatus(for: .event))
        guard status == "authorized" else {
            emit(HelperOutput(status: status, events: [], error: nil))
        }

        let start = Date()
        let end = start.addingTimeInterval(TimeInterval(horizonMinutes * 60))
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate).map { event in
            EventRecord(
                id: event.eventIdentifier ?? event.calendarItemIdentifier,
                title: String((event.title ?? "").prefix(240)),
                start: event.startDate,
                end: event.endDate,
                allDay: event.isAllDay
            )
        }
        emit(HelperOutput(status: status, events: events, error: nil))
    }
}
