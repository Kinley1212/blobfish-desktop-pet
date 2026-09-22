import AppKit

/// Wall-clock deadlines also expire while the Mac sleeps.
struct PetCoralHide {
    static let minutes = [1, 5, 15, 30]
    let startedAt: Date
    let deadline: Date
    init(minutes: Int, now: Date = Date()) {
        startedAt = now
        deadline = now.addingTimeInterval(Double(minutes) * 60)
    }
    func progress(at now: Date) -> CGFloat {
        CGFloat(min(1, max(0, (now.timeIntervalSince(startedAt) - 2) / 1.8)))
    }
}

/// One reversible timeline: reveal coral, swim behind it, fade the whole scene.
struct CoralHideFrame {
    let travel: CGFloat
    let coralOpacity: CGFloat
    let sceneOpacity: CGFloat
    init(progress: CGFloat) {
        let p = min(1, max(0, progress))
        let linear = min(1, max(0, (p - 0.2) / 0.55))
        travel = linear * linear * (3 - 2 * linear)
        coralOpacity = min(1, p / 0.2)
        sceneOpacity = 1 - min(1, max(0, (p - 0.75) / 0.25))
    }
}

final class CoralRefugeView: NSView {
    var refugeRect: NSRect = .zero { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard refugeRect.width > 0, refugeRect.height > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: refugeRect.minX, yBy: refugeRect.minY)
        transform.scaleX(by: refugeRect.width / 150, yBy: refugeRect.height / 100)
        transform.concat()
        let center: CGFloat = 75
        for (index, x) in [-55.0, -28, 0, 28, 55].enumerated() {
            let color = index.isMultiple(of: 2)
                ? NSColor(calibratedRed: 0.94, green: 0.52, blue: 0.57, alpha: 1)
                : NSColor(calibratedRed: 0.73, green: 0.48, blue: 0.67, alpha: 1)
            color.setStroke()
            let base = CGPoint(x: center + x * 0.65, y: 12)
            let tip = CGPoint(x: center + x, y: 65 + Double(index % 3) * 13)
            let branch = NSBezierPath()
            branch.lineWidth = 12; branch.lineCapStyle = .round
            branch.move(to: base)
            branch.curve(to: tip, controlPoint1: CGPoint(x: base.x - 8, y: 40), controlPoint2: CGPoint(x: tip.x + 5, y: 48))
            branch.move(to: CGPoint(x: (base.x + tip.x) / 2, y: 40))
            branch.line(to: CGPoint(x: tip.x - 16, y: 59))
            branch.move(to: CGPoint(x: tip.x, y: 52))
            branch.line(to: CGPoint(x: tip.x + 14, y: 69))
            branch.stroke()
        }
        NSColor(calibratedRed: 0.43, green: 0.69, blue: 0.65, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: center - 66, y: 3, width: 132, height: 20)).fill()
    }
}
