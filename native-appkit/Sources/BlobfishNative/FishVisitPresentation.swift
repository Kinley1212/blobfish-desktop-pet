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
    static let duration: TimeInterval = 1.25
    let progress: CGFloat
    init(elapsed: TimeInterval, reducedMotion: Bool = false) {
        progress = reducedMotion ? 1 : CGFloat(min(1, max(0, elapsed / Self.duration)))
    }
    var guestProgress: CGFloat {
        let value = min(1, max(0, (progress - 0.22) / 0.56))
        return value * value * (3 - 2 * value)
    }
    var doorOpacity: CGFloat { min(1, progress / 0.12) * min(1, (1 - progress) / 0.2) }
    var opening: CGFloat { min(1, max(0, (progress - 0.12) / 0.3)) }
}

/// A local, non-interactive drawing behind the guest; no image assets or timers.
final class FishVisitDoorView: NSView {
    var arrival = FishVisitArrival(elapsed: 0) { didSet { needsDisplay = true } }
    var characterRect = NSRect.zero { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard arrival.doorOpacity > 0 else { return }
        let rect = characterRect.insetBy(dx: -5, dy: -6).intersection(bounds.insetBy(dx: 3, dy: 3))
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
