import AppKit

struct FishPendingVisit: Equatable {
    static let timeout: TimeInterval = 40
    let requestID: UUID
    let contactID: UUID
    let startedAt: Date

    static func invitationIsFresh(sentAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(sentAt)
        return age >= -5 && age < timeout
    }

    func accepts(contactID: UUID, replyTo: UUID?, sentAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(startedAt)
        guard self.contactID == contactID, age >= 0, age < Self.timeout else { return false }
        // Older peers do not echo replyTo. Only accept a fresh response from
        // the currently dialled peer, never cached or unsolicited acceptance.
        return replyTo.map { $0 == requestID } ?? (sentAt >= startedAt)
    }
}

struct FishVisitArrival {
    static let duration: TimeInterval = 2.4
    static let initialScale: CGFloat = 0.28
    let progress: CGFloat
    init(elapsed: TimeInterval, reducedMotion: Bool = false) {
        progress = reducedMotion ? 1 : CGFloat(min(1, max(0, elapsed / Self.duration)))
    }
    var guestProgress: CGFloat {
        let value = min(1, max(0, (progress - 0.18) / 0.54))
        return value * value * (3 - 2 * value)
    }
    // Keep the doorway fully visible through arrival and a short settled hold.
    var doorOpacity: CGFloat { min(1, progress / 0.1) * min(1, (1 - progress) / 0.16) }
    var opening: CGFloat { min(1, max(0, (progress - 0.04) / 0.14)) }
    var walkingBob: CGFloat {
        // Gentle walking sway, smoothly zero at the doorway and the landing.
        guard guestProgress > 0, guestProgress < 1 else { return 0 }
        return 4 * sin(guestProgress * .pi) * sin(guestProgress * 3 * .pi)
    }
}

struct FishVisitArrivalPath {
    let startOffset: NSPoint
    let doorRect: NSRect
    init(character: NSRect, canvas: NSRect, ownerIsLeft: Bool) {
        let size = NSSize(width: character.width * 0.38 + 12, height: character.height * 0.38 + 14)
        let room = canvas.insetBy(dx: 5, dy: 5)
        let desiredX = character.midX + (ownerIsLeft ? 40 : -40)
        let centerX = max(room.minX + size.width / 2, min(room.maxX - size.width / 2, desiredX))
        let centerY = max(room.minY + size.height / 2, min(room.maxY - size.height / 2, character.midY + 62))
        startOffset = NSPoint(x: centerX - character.midX, y: centerY - character.midY)
        doorRect = NSRect(x: centerX - size.width / 2, y: centerY - size.height / 2, width: size.width, height: size.height)
    }
    func offset(at progress: CGFloat) -> NSPoint {
        NSPoint(x: startOffset.x * (1 - progress), y: startOffset.y * (1 - progress))
    }
}

enum FishVisitCallArt {
    static let image = NSImage(size: NSSize(width: 72, height: 72), flipped: false) { _ in
        NSColor(calibratedRed: 0.88, green: 0.53, blue: 0.65, alpha: 0.25).setFill()
        NSBezierPath(ovalIn: NSRect(x: 5, y: 2, width: 62, height: 62)).fill()
        NSColor(calibratedRed: 1, green: 0.91, blue: 0.94, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 5, y: 7, width: 62, height: 62)).fill()
        let ink = NSColor(calibratedRed: 0.75, green: 0.27, blue: 0.45, alpha: 1)
        NSImage(systemSymbolName: "phone.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [ink]))?
            .draw(in: NSRect(x: 21, y: 22, width: 30, height: 32))
        ink.withAlphaComponent(0.55).setFill()
        for x: CGFloat in [11, 57] {
            NSBezierPath(roundedRect: NSRect(x: x, y: 31, width: 4, height: 13), xRadius: 2, yRadius: 2).fill()
        }
        return true
    }

    static func ringingAnimation() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = [0, -0.18, 0.18, -0.14, 0.14, -0.08, 0.08, 0, 0]
        animation.keyTimes = [0, 0.07, 0.14, 0.21, 0.28, 0.35, 0.42, 0.49, 1]
        animation.duration = 1.35
        animation.repeatCount = .infinity
        return animation
    }
}

/// A local, non-interactive drawing behind the guest; no image assets or timers.
final class FishVisitDoorView: NSView {
    var arrival = FishVisitArrival(elapsed: 0) { didSet { needsDisplay = true } }
    var doorRect = NSRect.zero { didSet { if oldValue != doorRect { needsDisplay = true } } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard arrival.doorOpacity > 0 else { return }
        let rect = doorRect.intersection(bounds.insetBy(dx: 3, dy: 3))
        guard !rect.isEmpty else { return }
        let alpha = arrival.doorOpacity
        NSColor(calibratedRed: 1, green: 0.77, blue: 0.83, alpha: alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18).fill()
        let inside = rect.insetBy(dx: 5, dy: 5)
        NSColor(calibratedRed: 0.43, green: 0.23, blue: 0.33, alpha: alpha).setFill()
        NSBezierPath(roundedRect: inside, xRadius: 14, yRadius: 14).fill()
        let leaf = NSRect(x: inside.minX, y: inside.minY, width: inside.width * (1 - 0.94 * arrival.opening), height: inside.height)
        NSColor(calibratedRed: 1, green: 0.9, blue: 0.87, alpha: alpha).setFill()
        NSBezierPath(roundedRect: leaf, xRadius: 10, yRadius: 10).fill()
        if leaf.width > 18 {
            NSColor(calibratedRed: 0.77, green: 0.4, blue: 0.45, alpha: alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: leaf.maxX - 12, y: leaf.midY, width: 5, height: 5)).fill()
        }
    }
}
