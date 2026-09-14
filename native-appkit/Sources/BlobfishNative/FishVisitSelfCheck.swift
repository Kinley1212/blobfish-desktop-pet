import AppKit

extension SelfCheck {
    static func visitHandshakeRejectsStaleResponses() -> Bool {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let friend = UUID(), other = UUID()
        for index in 0..<1000 {
            let request = UUID()
            let waiting = FishPendingVisit(requestID: request, contactID: friend, startedAt: now)
            let responseTime = now.addingTimeInterval(Double(index % 39))
            guard waiting.accepts(contactID: friend, replyTo: request, sentAt: now, now: responseTime),
                  !waiting.accepts(contactID: other, replyTo: request, sentAt: now, now: responseTime),
                  !waiting.accepts(contactID: friend, replyTo: UUID(), sentAt: now, now: responseTime),
                  !waiting.accepts(contactID: friend, replyTo: request, sentAt: now, now: now.addingTimeInterval(40)),
                  !waiting.accepts(contactID: friend, replyTo: nil, sentAt: now.addingTimeInterval(-1), now: responseTime),
                  waiting.accepts(contactID: friend, replyTo: nil, sentAt: responseTime, now: responseTime) else { return false }
            let replacement = FishPendingVisit(requestID: UUID(), contactID: friend, startedAt: now)
            guard !replacement.accepts(contactID: friend, replyTo: request, sentAt: responseTime, now: responseTime) else { return false }
        }
        return FishPendingVisit.invitationIsFresh(sentAt: now, now: now.addingTimeInterval(8))
            && !FishPendingVisit.invitationIsFresh(sentAt: now, now: now.addingTimeInterval(40))
            && !FishPendingVisit.invitationIsFresh(sentAt: now.addingTimeInterval(60), now: now)
    }

    static func visitArrivalPreservesMovementBounds() -> Bool {
        let view = PetView(frame: NSRect(x: 0, y: 0, width: 170, height: 165), contentMode: .artwork)
        let movement = view.movementBounds
        let character = view.characterBounds
        var lastGuest: CGFloat = 0
        for frame in 0...180 {
            let arrival = FishVisitArrival(elapsed: Double(frame) / 120)
            guard (0...1).contains(arrival.progress), (0...1).contains(arrival.doorOpacity),
                  (0...1).contains(arrival.opening), arrival.guestProgress >= lastGuest else { return false }
            lastGuest = arrival.guestProgress
            view.arrivalProgress = arrival.guestProgress
            guard view.movementBounds == movement, view.characterBounds == character else { return false }
        }
        let opening = FishVisitArrival(elapsed: 0.2)
        let complete = FishVisitArrival(elapsed: 2)
        let reduced = FishVisitArrival(elapsed: 0, reducedMotion: true)
        return opening.guestProgress == 0 && opening.doorOpacity > 0
            && complete.guestProgress == 1 && complete.doorOpacity == 0
            && reduced.guestProgress == 1 && reduced.doorOpacity == 0
    }
}
