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
        let path = FishVisitArrivalPath(character: character, canvas: view.bounds, ownerIsLeft: true)
        guard path.startOffset.x > 0, path.startOffset.y > 0, view.bounds.contains(path.doorRect) else { return false }
        var sawUp = false, sawDown = false
        for frame in 0...360 {
            let arrival = FishVisitArrival(elapsed: Double(frame) / 120)
            guard (0...1).contains(arrival.progress), (0...1).contains(arrival.doorOpacity),
                  (0...1).contains(arrival.opening), arrival.guestProgress >= lastGuest else { return false }
            lastGuest = arrival.guestProgress
            view.arrivalProgress = arrival.guestProgress
            let offset = path.offset(at: arrival.guestProgress)
            view.arrivalOffset = NSPoint(x: offset.x, y: offset.y + arrival.walkingBob)
            guard abs(arrival.walkingBob) <= 4 else { return false }
            sawUp = sawUp || arrival.walkingBob > 0.1
            sawDown = sawDown || arrival.walkingBob < -0.1
            if arrival.guestProgress > 0 { guard arrival.opening == 1 else { return false } }
            if arrival.guestProgress > 0, arrival.guestProgress < 1 {
                guard arrival.doorOpacity == 1 else { return false }
            }
            guard view.movementBounds == movement, view.characterBounds == character else { return false }
        }
        let opening = FishVisitArrival(elapsed: 0.2)
        let complete = FishVisitArrival(elapsed: 3)
        let landed = FishVisitArrival(elapsed: FishVisitArrival.duration * 0.78)
        let reduced = FishVisitArrival(elapsed: 0, reducedMotion: true)
        let leftPath = FishVisitArrivalPath(character: character, canvas: view.bounds, ownerIsLeft: false)
        return sawUp && sawDown && path.offset(at: 1) == .zero && leftPath.startOffset.x < 0
            && opening.guestProgress == 0 && opening.doorOpacity > 0
            && landed.guestProgress == 1 && landed.doorOpacity == 1 && landed.walkingBob == 0
            && complete.guestProgress == 1 && complete.doorOpacity == 0
            && reduced.guestProgress == 1 && reduced.doorOpacity == 0
    }

    static func visitCallAnimationLifecycle() -> Bool {
        let view = PetView(frame: NSRect(x: 0, y: 0, width: 340, height: 240), contentMode: .overlay)
        view.visitCalling = true
        view.updateVisitCallMotion(reducedMotion: false)
        guard let layer = view.layer?.sublayers?.first(where: { $0.name == "visit-call" }),
              let animation = layer.animation(forKey: "ringing") as? CAKeyframeAnimation,
              !layer.isHidden, animation.duration == 1.35,
              animation.values?.count == 9, animation.keyTimes?.last == 1 else { return false }
        view.updateVisitCallMotion(reducedMotion: true)
        guard !layer.isHidden, layer.animation(forKey: "ringing") == nil else { return false }
        view.updateVisitCallMotion(reducedMotion: false)
        guard layer.animation(forKey: "ringing") != nil else { return false }
        view.visitCalling = false
        return layer.isHidden && layer.animation(forKey: "ringing") == nil
    }
}
