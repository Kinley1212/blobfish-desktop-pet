import AppKit

final class PetPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Most of this borderless panel is deliberately transparent space for
        // speech and task cards. AppKit's default constraint treats that space
        // as visible window content and pulls the whole panel back on-screen
        // when the pet reaches the menu-bar edge. PetMovementGeometry already
        // constrains the actual artwork, so preserve the requested panel frame.
        frameRect
    }
}

enum PetMotionTiming {
    enum State { case idle, roam, working, waiting }
    static let framesPerSecond = 60.0
    static let pointsPerSecondPerSpeedUnit = 1_000.0 / 30.0
    static let swimPeriod = 0.9
    static let swimDistance = 5.0
    static let bobVisibilityTransitionDuration: TimeInterval = 0.2

    static func cubicBezier(
        _ progress: Double,
        x1: Double, y1: Double,
        x2: Double, y2: Double
    ) -> Double {
        let x = min(1, max(0, progress))
        func value(_ t: Double, _ first: Double, _ second: Double) -> Double {
            let inverse = 1 - t
            return 3 * inverse * inverse * t * first
                + 3 * inverse * t * t * second
                + t * t * t
        }
        func derivative(_ t: Double, _ first: Double, _ second: Double) -> Double {
            3 * (1 - t) * (1 - t) * first
                + 6 * (1 - t) * t * (second - first)
                + 3 * t * t * (1 - second)
        }
        var t = x
        for _ in 0..<6 {
            let slope = derivative(t, x1, x2)
            guard abs(slope) > 0.000_001 else { break }
            t = min(1, max(0, t - (value(t, x1, x2) - x) / slope))
        }
        return value(t, y1, y2)
    }

    static func easeInOut(_ progress: Double) -> Double {
        cubicBezier(progress, x1: 0.42, y1: 0, x2: 0.58, y2: 1)
    }

    static func travelDistance(speed: Double, elapsed: TimeInterval) -> CGFloat {
        CGFloat(speed * pointsPerSecondPerSpeedUnit * max(0, min(elapsed, 0.05)))
    }

    static func advancedBobElapsed(
        current: TimeInterval,
        frameElapsed: TimeInterval,
        paused: Bool
    ) -> TimeInterval {
        guard !paused else { return current }
        return current + max(0, min(frameElapsed, 0.05))
    }

    static func transitionedBobVisibility(
        current: CGFloat,
        frameElapsed: TimeInterval,
        paused: Bool
    ) -> CGFloat {
        let normalized = min(1, max(0, current))
        let elapsed = max(0, min(frameElapsed, 0.05))
        let step = CGFloat(elapsed / bobVisibilityTransitionDuration)
        return paused
            ? max(0, normalized - step)
            : min(1, normalized + step)
    }

    static func swimOffset(elapsed: TimeInterval, characterID: String = "blobfish", state: State = .idle) -> CGFloat {
        let period: TimeInterval
        let distance: Double
        if characterID == "grass-buddy" {
            switch state {
            case .idle: period = 3.6; distance = 2
            case .roam: period = 0.84; distance = 4
            case .working: period = 1.25; distance = 3
            case .waiting: period = 2.8; distance = 1
            }
        } else {
            period = swimPeriod
            distance = swimDistance
        }
        let phase = elapsed.truncatingRemainder(dividingBy: period) / period
        let leg = phase <= 0.5 ? phase * 2 : (1 - phase) * 2
        return CGFloat(easeInOut(leg) * distance)
    }
}

enum PetMovementPause {
    static func shouldPause(
        hovering: Bool,
        menuOpen: Bool,
        interacting: Bool,
        dragging: Bool,
        flinging: Bool
    ) -> Bool {
        menuOpen || interacting || dragging || (hovering && !flinging)
    }
}

enum PetMovementGeometry {
    static func allowedOrigins(visibleFrame: NSRect, visualBounds: NSRect) -> NSRect? {
        let width = visibleFrame.width - visualBounds.width
        let height = visibleFrame.height - visualBounds.height
        guard width >= 0, height >= 0,
              visibleFrame.width.isFinite, visibleFrame.height.isFinite,
              visualBounds.width.isFinite, visualBounds.height.isFinite else { return nil }
        return NSRect(
            x: visibleFrame.minX - visualBounds.minX,
            y: visibleFrame.minY - visualBounds.minY,
            width: width,
            height: height
        )
    }

    static func clamped(_ origin: NSPoint, to allowed: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, allowed.minX), allowed.maxX),
            y: min(max(origin.y, allowed.minY), allowed.maxY)
        )
    }

    static func allowedOrigins(
        visibleFrames: [NSRect],
        visualBounds: NSRect,
        currentOrigin: NSPoint
    ) -> NSRect? {
        let candidates = visibleFrames.compactMap { visibleFrame -> (visible: NSRect, allowed: NSRect)? in
            guard let allowed = allowedOrigins(visibleFrame: visibleFrame, visualBounds: visualBounds) else {
                return nil
            }
            return (visibleFrame, allowed)
        }
        guard !candidates.isEmpty else { return nil }

        // Keep using the current display whenever the pet is already valid on
        // it. Falling back to NSScreen.main here used to project a pet in a
        // display seam all the way down to the primary screen's lower edge.
        if let current = candidates.first(where: { $0.allowed.contains(currentOrigin) }) {
            return current.allowed
        }

        let visualCenter = NSPoint(
            x: currentOrigin.x + visualBounds.midX,
            y: currentOrigin.y + visualBounds.midY
        )
        if let centered = candidates.first(where: { $0.visible.contains(visualCenter) }) {
            return centered.allowed
        }

        return candidates.min { left, right in
            squaredDistance(from: currentOrigin, to: left.allowed)
                < squaredDistance(from: currentOrigin, to: right.allowed)
        }?.allowed
    }

    private static func squaredDistance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let projected = clamped(point, to: rect)
        let dx = projected.x - point.x
        let dy = projected.y - point.y
        return dx * dx + dy * dy
    }
}

enum FishInteractionAnimationGeometry {
    static func launchOrigin(
        original: NSPoint,
        target: NSPoint,
        phase: CGFloat,
        allowed: NSRect
    ) -> NSPoint {
        let value = min(1, max(0, phase))
        let origin: NSPoint
        switch value {
        case ..<0.12:
            origin = original
        case ..<0.35:
            let local = (value - 0.12) / 0.23
            let eased = 1 - pow(1 - local, 3)
            origin = NSPoint(
                x: original.x + (target.x - original.x) * eased,
                y: original.y + (target.y - original.y) * eased + sin(local * .pi) * 72
            )
        case ..<0.77:
            let wobble = sin((value - 0.35) / 0.42 * .pi * 7) * 5
            origin = NSPoint(x: target.x + wobble, y: target.y)
        default:
            let local = (value - 0.77) / 0.23
            let eased = local * local * (3 - 2 * local)
            origin = NSPoint(
                x: target.x + (original.x - target.x) * eased,
                y: target.y + (original.y - target.y) * eased
            )
        }
        return PetMovementGeometry.clamped(origin, to: allowed)
    }

    static func vortexOrigin(
        original: NSPoint,
        center: NSPoint,
        opposite: NSPoint,
        phase: CGFloat,
        allowed: NSRect
    ) -> NSPoint {
        let value = min(1, max(0, phase))
        let origin: NSPoint
        if value < 0.38 {
            let local = value / 0.38
            let radius = (1 - local) * 34
            origin = NSPoint(
                x: original.x + (center.x - original.x) * local + cos(local * .pi * 5) * radius,
                y: original.y + (center.y - original.y) * local + sin(local * .pi * 5) * radius
            )
        } else if value < 0.55 {
            origin = value < 0.47 ? center : opposite
        } else {
            let local = (value - 0.55) / 0.45
            let eased = local * local * (3 - 2 * local)
            origin = NSPoint(
                x: opposite.x + (original.x - opposite.x) * eased,
                y: opposite.y + (original.y - opposite.y) * eased
            )
        }
        return PetMovementGeometry.clamped(origin, to: allowed)
    }

    static func waveOrigin(
        original: NSPoint,
        edge: NSPoint,
        phase: CGFloat,
        allowed: NSRect
    ) -> NSPoint {
        let value = min(1, max(0, phase))
        let local = value < 0.42 ? value / 0.42 : (1 - value) / 0.58
        let eased = max(0, local) * max(0, local) * (3 - 2 * max(0, local))
        return PetMovementGeometry.clamped(NSPoint(
            x: original.x + (edge.x - original.x) * eased,
            y: original.y + sin(value * .pi * 4) * 8
        ), to: allowed)
    }

    static func bubbleOrigin(
        original: NSPoint,
        center: NSPoint,
        phase: CGFloat,
        allowed: NSRect
    ) -> NSPoint {
        let value = min(1, max(0, phase))
        let local: CGFloat
        if value < 0.38 { local = value / 0.38 }
        else if value < 0.68 { local = 1 }
        else { local = (1 - value) / 0.32 }
        let eased = max(0, local) * max(0, local) * (3 - 2 * max(0, local))
        return PetMovementGeometry.clamped(NSPoint(
            x: original.x + (center.x - original.x) * eased + sin(value * .pi * 6) * 10,
            y: original.y + (center.y - original.y) * eased + sin(value * .pi * 3) * 18
        ), to: allowed)
    }
}

final class FishInteractionEffectView: NSView {
    enum Kind { case launch, bomb, vortex, wave, bubble, hearts, pet, highFive }

    let kind: Kind
    var phase: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    init(kind: Kind, frame: NSRect) {
        self.kind = kind
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        switch kind {
        case .launch: drawLaunch()
        case .bomb: drawBomb()
        case .vortex: drawVortex()
        case .wave: drawWave()
        case .bubble: drawBubble()
        case .hearts: drawHearts()
        case .pet: drawPettingRipples()
        case .highFive: drawHighFiveBurst()
        }
    }

    private var fade: CGFloat { min(1, max(0, (1 - phase) / 0.16)) }

    private func drawLaunch() {
        let progress = min(1, max(0, phase))
        NSColor.systemPink.withAlphaComponent(0.7 * fade).setStroke()
        for index in 0..<3 {
            let inset = CGFloat(index) * 8
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 12 + inset, y: 20 + inset * 0.4))
            path.curve(
                to: NSPoint(x: bounds.maxX - 14, y: bounds.maxY - 20 - inset * 0.3),
                controlPoint1: NSPoint(x: bounds.midX - 18, y: bounds.maxY - 4),
                controlPoint2: NSPoint(x: bounds.midX + 20, y: bounds.maxY - 8)
            )
            path.lineWidth = max(1, 4 - CGFloat(index))
            path.stroke()
        }
        let pulse = 8 + 6 * sin(progress * .pi)
        NSColor.systemPink.withAlphaComponent(0.85 * fade).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: bounds.maxX - 28 - pulse / 2, y: bounds.maxY - 31 - pulse / 2,
            width: pulse, height: pulse
        )).fill()
    }

    private func drawBomb() {
        if phase < 0.52 {
            let local = phase / 0.52
            let center = NSPoint(x: bounds.midX, y: bounds.midY - 5)
            NSColor(calibratedWhite: 0.12, alpha: 0.96).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 23, y: center.y - 23, width: 46, height: 46)).fill()
            NSColor.systemPink.setStroke()
            let fuse = NSBezierPath()
            fuse.move(to: NSPoint(x: center.x + 13, y: center.y + 17))
            fuse.curve(
                to: NSPoint(x: center.x + 25, y: center.y + 31),
                controlPoint1: NSPoint(x: center.x + 17, y: center.y + 23),
                controlPoint2: NSPoint(x: center.x + 23, y: center.y + 23)
            )
            fuse.lineWidth = 4
            fuse.stroke()
            let countdown = "\(max(1, 3 - Int(local * 3)))" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let size = countdown.size(withAttributes: attributes)
            countdown.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
            return
        }
        let local = min(1, (phase - 0.52) / 0.48)
        let alpha = min(1, max(0, (1 - local) / 0.35))
        NSColor.systemPink.withAlphaComponent(0.72 * alpha).setFill()
        let centers = [
            NSPoint(x: bounds.midX - 26, y: bounds.midY),
            NSPoint(x: bounds.midX, y: bounds.midY + 16),
            NSPoint(x: bounds.midX + 27, y: bounds.midY + 2),
            NSPoint(x: bounds.midX, y: bounds.midY - 16),
        ]
        for (index, center) in centers.enumerated() {
            let radius = 24 + CGFloat(index % 2) * 7 + local * 13
            NSBezierPath(ovalIn: NSRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            )).fill()
        }
        NSColor.black.withAlphaComponent(0.48 * alpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.midX - 28, y: bounds.midY - 20, width: 56, height: 48)).fill()
    }

    private func drawVortex() {
        let alpha = 0.82 * fade
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        for index in 0..<5 {
            let radius = CGFloat(16 + index * 11)
            let path = NSBezierPath()
            path.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: CGFloat(index * 54) + phase * 720,
                endAngle: CGFloat(index * 54 + 225) + phase * 720
            )
            path.lineWidth = max(2, 7 - CGFloat(index))
            NSColor(calibratedRed: 0.28, green: 0.66, blue: 0.82, alpha: alpha * (1 - CGFloat(index) * 0.11)).setStroke()
            path.stroke()
        }
        for index in 0..<8 {
            let angle = CGFloat(index) / 8 * .pi * 2 - phase * .pi * 3
            let radius = 40 + CGFloat(index % 3) * 13
            let size = 3 + CGFloat(index % 2) * 2
            NSColor(calibratedRed: 0.62, green: 0.90, blue: 1, alpha: alpha * 0.9).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: center.x + cos(angle) * radius - size,
                y: center.y + sin(angle) * radius * 0.62 - size,
                width: size * 2, height: size * 2
            )).fill()
        }
    }

    private func drawWave() {
        let lift = sin(min(1, phase) * .pi) * 10
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 12))
        path.line(to: NSPoint(x: 0, y: 48 + lift))
        path.curve(
            to: NSPoint(x: bounds.width * 0.52, y: 48 + lift),
            controlPoint1: NSPoint(x: bounds.width * 0.16, y: 82 + lift),
            controlPoint2: NSPoint(x: bounds.width * 0.35, y: 18 + lift)
        )
        path.curve(
            to: NSPoint(x: bounds.maxX, y: 54 + lift),
            controlPoint1: NSPoint(x: bounds.width * 0.70, y: 84 + lift),
            controlPoint2: NSPoint(x: bounds.width * 0.86, y: 30 + lift)
        )
        path.line(to: NSPoint(x: bounds.maxX, y: 12))
        path.close()
        NSColor(calibratedRed: 0.22, green: 0.66, blue: 0.90, alpha: 0.58 * fade).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.76 * fade).setStroke()
        path.lineWidth = 3
        path.stroke()
        for index in 0..<9 {
            let x = CGFloat(index) / 8 * bounds.width
            let y = 49 + lift + sin(CGFloat(index) * 1.7 + phase * .pi * 4) * 9
            let radius = 3 + CGFloat(index % 3)
            NSColor.white.withAlphaComponent(0.76 * fade).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: x - radius, y: y - radius,
                width: radius * 2, height: radius * 2
            )).fill()
        }
    }

    private func drawBubble() {
        if phase < 0.76 {
            let grow = min(1, phase / 0.18)
            let radius = (54 + sin(phase * .pi * 5) * 3) * grow
            let rect = NSRect(
                x: bounds.midX - radius, y: bounds.midY - radius,
                width: radius * 2, height: radius * 2
            )
            NSColor(calibratedRed: 0.58, green: 0.86, blue: 1, alpha: 0.13).setFill()
            NSBezierPath(ovalIn: rect).fill()
            NSColor(calibratedRed: 0.42, green: 0.76, blue: 0.96, alpha: 0.82).setStroke()
            let ring = NSBezierPath(ovalIn: rect)
            ring.lineWidth = 4
            ring.stroke()
            NSColor.white.withAlphaComponent(0.82).setStroke()
            let shine = NSBezierPath()
            shine.appendArc(
                withCenter: NSPoint(x: rect.midX - radius * 0.24, y: rect.midY + radius * 0.18),
                radius: radius * 0.58,
                startAngle: 108,
                endAngle: 166
            )
            shine.lineWidth = 5
            shine.stroke()
            for index in 0..<5 {
                let angle = CGFloat(index) * 1.42 + phase * .pi
                let orbit = radius + 12 + CGFloat(index % 2) * 8
                let small = 3 + CGFloat(index % 3)
                NSColor(calibratedRed: 0.48, green: 0.80, blue: 1, alpha: 0.72).setStroke()
                let smallBubble = NSBezierPath(ovalIn: NSRect(
                    x: bounds.midX + cos(angle) * orbit - small,
                    y: bounds.midY + sin(angle) * orbit - small,
                    width: small * 2, height: small * 2
                ))
                smallBubble.lineWidth = 1.5
                smallBubble.stroke()
            }
        } else {
            let burst = min(1, (phase - 0.76) / 0.24)
            NSColor(calibratedRed: 0.42, green: 0.76, blue: 0.96, alpha: 0.9 * (1 - burst)).setStroke()
            for index in 0..<10 {
                let angle = CGFloat(index) / 10 * .pi * 2
                let inner = 46 + burst * 18
                let outer = inner + 13
                let path = NSBezierPath()
                path.move(to: NSPoint(x: bounds.midX + cos(angle) * inner, y: bounds.midY + sin(angle) * inner))
                path.line(to: NSPoint(x: bounds.midX + cos(angle) * outer, y: bounds.midY + sin(angle) * outer))
                path.lineWidth = 3
                path.stroke()
            }
        }
    }

    private func drawHearts() {
        for index in 0..<5 {
            let delay = CGFloat(index) * 0.11
            let local = min(1, max(0, (phase - delay) / max(0.1, 1 - delay)))
            guard local > 0 else { continue }
            let x = bounds.midX + sin(CGFloat(index) * 2.2) * 38
            let y = 16 + local * (bounds.height - 30)
            let scale = 0.65 + CGFloat(index % 3) * 0.15
            let path = Self.heartPath(center: NSPoint(x: x, y: y), size: 18 * scale)
            NSColor.systemPink.withAlphaComponent((1 - local) * 0.9).setFill()
            path.fill()
        }
    }

    private func drawPettingRipples() {
        for index in 0..<3 {
            let delayed = min(1, max(0, phase * 1.35 - CGFloat(index) * 0.18))
            guard delayed > 0 else { continue }
            let radius = 12 + delayed * 42
            NSColor.systemPink.withAlphaComponent((1 - delayed) * 0.68).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(
                x: bounds.midX - radius,
                y: bounds.midY - radius * 0.42,
                width: radius * 2,
                height: radius * 0.84
            ))
            ring.lineWidth = 3.5 - CGFloat(index) * 0.6
            ring.stroke()
        }
        for index in 0..<6 {
            let angle = CGFloat(index) / 6 * .pi * 2 + phase * .pi
            let radius = 24 + phase * 20
            let dot = 3 + CGFloat(index % 2) * 1.5
            NSColor.systemPink.withAlphaComponent(0.72 * fade).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: bounds.midX + cos(angle) * radius - dot,
                y: bounds.midY + sin(angle) * radius * 0.52 - dot,
                width: dot * 2, height: dot * 2
            )).fill()
        }
    }

    private func drawHighFiveBurst() {
        let local = min(1, max(0, phase))
        let alpha = fade
        for index in 0..<12 {
            let angle = CGFloat(index) / 12 * .pi * 2
            let inner = 12 + local * 16
            let outer = inner + 15 + CGFloat(index % 3) * 3
            let path = NSBezierPath()
            path.move(to: NSPoint(
                x: bounds.midX + cos(angle) * inner,
                y: bounds.midY + sin(angle) * inner
            ))
            path.line(to: NSPoint(
                x: bounds.midX + cos(angle) * outer,
                y: bounds.midY + sin(angle) * outer
            ))
            path.lineWidth = index.isMultiple(of: 2) ? 4 : 2
            (index.isMultiple(of: 2) ? NSColor.systemYellow : NSColor.systemPink)
                .withAlphaComponent(0.82 * alpha).setStroke()
            path.stroke()
        }
        NSColor.white.withAlphaComponent(0.82 * alpha).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: bounds.midX - 10, y: bounds.midY - 10, width: 20, height: 20
        )).fill()
    }

    private static func heartPath(center: NSPoint, size: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x, y: center.y - size * 0.48))
        path.curve(
            to: NSPoint(x: center.x - size * 0.50, y: center.y + size * 0.05),
            controlPoint1: NSPoint(x: center.x - size * 0.12, y: center.y - size * 0.24),
            controlPoint2: NSPoint(x: center.x - size * 0.50, y: center.y - size * 0.22)
        )
        path.curve(
            to: NSPoint(x: center.x, y: center.y + size * 0.45),
            controlPoint1: NSPoint(x: center.x - size * 0.50, y: center.y + size * 0.34),
            controlPoint2: NSPoint(x: center.x - size * 0.20, y: center.y + size * 0.50)
        )
        path.curve(
            to: NSPoint(x: center.x + size * 0.50, y: center.y + size * 0.05),
            controlPoint1: NSPoint(x: center.x + size * 0.20, y: center.y + size * 0.50),
            controlPoint2: NSPoint(x: center.x + size * 0.50, y: center.y + size * 0.34)
        )
        path.curve(
            to: NSPoint(x: center.x, y: center.y - size * 0.48),
            controlPoint1: NSPoint(x: center.x + size * 0.50, y: center.y - size * 0.22),
            controlPoint2: NSPoint(x: center.x + size * 0.12, y: center.y - size * 0.24)
        )
        path.close()
        return path
    }
}

enum PetFormationGeometry {
    static func movementBounds(
        primaryBounds: NSRect,
        companionFrame: NSRect?,
        companionBounds: NSRect?
    ) -> NSRect {
        guard let companionFrame, let companionBounds else { return primaryBounds }
        return primaryBounds.union(
            companionBounds.offsetBy(dx: companionFrame.minX, dy: companionFrame.minY)
        )
    }
}

final class PetPanelController {
    let panel: NSPanel
    private(set) var sceneAnchor: PetSceneAnchor?
    private let overlayPanel: NSPanel
    private let petView: PetView
    private let guestView: PetView
    private let overlayView: PetView
    private lazy var movementDisplayLink = DisplayLinkDriver { [weak self] _ in
        self?.moveOneFrame()
    }
    private var movementDirection: CGFloat = 1
    private var taskWantsMovement = false
    private var hasActiveTasks = false
    private var movementEnabled = false
    private var bobBaselineY: CGFloat?
    private var preciseOrigin: NSPoint?
    private var lastFrameUptime: TimeInterval?
    private let motionStartUptime = ProcessInfo.processInfo.systemUptime
    private var bobElapsed: TimeInterval = 0
    private var bobVisibility: CGFloat = 1
    private var lastAutomaticOrigin: NSPoint?
    private var config: AppConfig
    private var interactionTimer: Timer?
    private var remoteInteractionTimer: Timer?
    private var remoteInteractionOriginalOrigin: NSPoint?
    private var remoteInteractionGuestOriginalFrame: NSRect?
    private var remoteInteractionOverlays: [NSView] = []
    private var friendBubbleTimer: Timer?
    private var speakingTimers: [PetMessageSpeaker: Timer] = [:]
    private var speakingPresentations: [PetMessageSpeaker: PetSpeakingPresentation] = [:]
    private var displayedVisitPresence: FishPresence?
    private var displayedVisitFriendName: String?
    private var visitAnnouncementWorkItem: DispatchWorkItem?
    private var interactionPaused = false
    private var composerPaused = false
    private var hoverPaused = false
    private var menuPaused = false
    private var dragging = false
    private var flingVelocity: CGVector?
    private var lastPointerX: CGFloat?
    private var pettingHistory: [(time: TimeInterval, dx: CGFloat)] = []
    private var pettingCooldownUntil: TimeInterval = 0
    private var pettingStreak = 0
    private var lastPettingAt: TimeInterval = 0
    private var motionState = PetMotionTiming.State.idle
    private var statusFaceID: String?

    var onClick: (() -> Void)? {
        didSet { petView.onClick = onClick }
    }
    var onDoubleClick: (() -> Void)? {
        didSet { petView.onDoubleClick = onDoubleClick }
    }
    var onRightDoubleClick: (() -> Void)? {
        didSet { petView.onRightDoubleClick = onRightDoubleClick }
    }
    var onSceneAnchorChanged: ((PetSceneAnchor) -> Void)? {
        didSet {
            if let sceneAnchor { onSceneAnchorChanged?(sceneAnchor) }
        }
    }
    var onSpeechBubbleClick: ((UUID?) -> Void)? {
        didSet { overlayView.onSpeechBubbleClick = onSpeechBubbleClick }
    }
    var onUnreadBadgeClick: (() -> Void)? {
        didSet { overlayView.onUnreadBadgeClick = onUnreadBadgeClick }
    }
    var onCompanionClick: (() -> Void)? {
        didSet {
            petView.onCompanionClick = onCompanionClick
            overlayView.onCompanionClick = onCompanionClick
        }
    }
    var onPetting: ((Int) -> Void)?
    var moodFaceProvider: ((String) -> String?)?
    private lazy var speechQueue = SpeechQueue(
        deliver: { [weak self] message in
            guard let self else { return }
            self.overlayView.transientMessage = message.text.isEmpty ? nil : message.text
            self.overlayView.transientMessageEvent = message.event
            self.overlayView.transientMessageColor = message.color
            self.petView.setMoodFace(message.faceID ?? message.event.flatMap { self.moodFaceProvider?($0) } ?? self.statusFaceID)
            self.show()
        },
        onIdle: { [weak self] in
            self?.overlayView.transientMessage = nil
            self?.overlayView.transientMessageEvent = nil
            self?.overlayView.transientMessageColor = nil
            self?.petView.setMoodFace(self?.statusFaceID)
        }
    )

    init(runtime: AppRuntime) {
        config = runtime.config
        let size = NSSize(width: 340, height: 165)
        let initialVisibleFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        panel = PetPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        overlayPanel = PetPanel(
            contentRect: initialVisibleFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        petView = PetView(frame: NSRect(origin: .zero, size: size), contentMode: .artwork)
        guestView = PetView(
            frame: NSRect(x: 168, y: 0, width: 170, height: 165),
            contentMode: .artwork
        )
        overlayView = PetView(
            frame: NSRect(origin: .zero, size: initialVisibleFrame.size),
            contentMode: .overlay
        )
        overlayView.autoresizingMask = [.width, .height]
        panel.contentView = petView
        overlayPanel.contentView = overlayView
        petView.addSubview(guestView)
        guestView.isHidden = true
        guestView.ignoresMouseInteraction = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "水滴鱼"
        overlayPanel.backgroundColor = .clear
        overlayPanel.isOpaque = false
        overlayPanel.hasShadow = false
        overlayPanel.level = .floating
        overlayPanel.hidesOnDeactivate = false
        overlayPanel.isMovableByWindowBackground = false
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlayPanel.ignoresMouseEvents = true
        overlayPanel.title = "水滴鱼场景层"
        petView.character = runtime.character
        overlayView.character = runtime.character
        petView.characterScale = config.pet.scale
        petView.accessoryPacks = runtime.accessories
        overlayView.accessoryPacks = runtime.accessories
        petView.accessorySpec = AppearanceJSON.accessorySpec(in: config, characterID: config.pet.characterPackId)
        petView.customization = config.pet.customization[config.pet.characterPackId]
        overlayView.performancePanelSide = config.performance.panelSide
        overlayView.performancePanelVerticalPosition = config.performance.panelVerticalPosition
        overlayView.performancePanelDistance = config.performance.panelDistance
        petView.onDragStart = { [weak self] in self?.beginDrag() }
        petView.onDragMove = { [weak self] dx, dy in self?.dragBy(dx: dx, dy: dy) }
        petView.onDragEnd = { [weak self] vx, vy in self?.endDrag(velocityX: vx, velocityY: vy) }
        overlayView.locale = config.ui.locale
        centerOnPrimaryScreen()
        syncSceneOverlay()
        syncMovementTimer()
    }

    func show() {
        panel.orderFrontRegardless()
        overlayPanel.orderFrontRegardless()
        syncSceneOverlay()
    }

    func update(snapshot: TaskSnapshot) {
        overlayView.snapshot = snapshot
        hasActiveTasks = snapshot.activeCount > 0
        taskWantsMovement = snapshot.state == .running
        motionState = snapshot.activeCount > 0
            ? (snapshot.state == .waiting ? .waiting : .working)
            : (movementEnabled ? .roam : .idle)
        petView.motionState = motionState
        syncMovementTimer()
    }

    func apply(runtime: AppRuntime) {
        config = runtime.config
        petView.character = runtime.character
        overlayView.character = runtime.character
        petView.characterScale = config.pet.scale
        petView.accessoryPacks = runtime.accessories
        overlayView.accessoryPacks = runtime.accessories
        petView.accessorySpec = AppearanceJSON.accessorySpec(in: config, characterID: config.pet.characterPackId)
        petView.customization = config.pet.customization[config.pet.characterPackId]
        overlayView.performancePanelSide = config.performance.panelSide
        overlayView.performancePanelVerticalPosition = config.performance.panelVerticalPosition
        overlayView.performancePanelDistance = config.performance.panelDistance
        overlayView.locale = config.ui.locale
        bobBaselineY = nil
        preciseOrigin = nil
        lastFrameUptime = nil
        lastAutomaticOrigin = nil
        syncSceneOverlay()
        syncMovementTimer()
    }

    func centerOnPrimaryScreen() {
        guard let visibleFrame = NSScreen.main?.visibleFrame else { return }
        let movementBounds = currentMovementBounds
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - movementBounds.midX,
            y: visibleFrame.minY - movementBounds.minY
        ))
        bobBaselineY = nil
        preciseOrigin = nil
        lastFrameUptime = nil
        lastAutomaticOrigin = nil
        syncSceneOverlay()
    }

    func stop() {
        movementDisplayLink.stop()
        interactionTimer?.invalidate()
        interactionTimer = nil
        cancelRemoteInteraction(restorePosition: false)
        friendBubbleTimer?.invalidate()
        friendBubbleTimer = nil
        speakingTimers.values.forEach { $0.invalidate() }
        speakingTimers.removeAll()
        speakingPresentations.removeAll()
        petView.clearSpeakingPresentation()
        guestView.clearSpeakingPresentation()
        speechQueue.clear()
        panel.orderOut(nil)
        overlayPanel.orderOut(nil)
    }

    func say(
        _ text: String,
        event: String? = nil,
        faceID: String? = nil,
        duration: TimeInterval = 7,
        priority: Int = 10,
        replaceKey: String? = nil,
        color: String? = nil
    ) {
        speechQueue.enqueue(
            text: text,
            event: event,
            faceID: faceID,
            priority: priority,
            duration: duration,
            replaceKey: replaceKey,
            color: color
        )
    }

    func playEffect(_ state: TaskDisplayState) { petView.playEffect(state) }

    func playCompletionEffect(all: Bool) {
        petView.playEffect(.completed)
        overlayView.playCompletionEffect(all: all)
    }

    func playClickReaction() {
        interactionTimer?.invalidate()
        interactionPaused = true
        petView.playClickEffect()
        interactionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.interactionPaused = false
            self?.interactionTimer = nil
        }
        RunLoop.main.add(interactionTimer!, forMode: .common)
    }

    func playCompanionHitReaction() {
        interactionTimer?.invalidate()
        interactionPaused = true
        guestView.playClickEffect()
        interactionTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: false) { [weak self] _ in
            self?.interactionPaused = false
            self?.interactionTimer = nil
        }
        RunLoop.main.add(interactionTimer!, forMode: .common)
    }

    func playRemoteInteraction(_ interaction: FishRemoteInteraction, incoming: Bool) {
        interactionTimer?.invalidate()
        cancelRemoteInteraction(restorePosition: true)
        interactionPaused = true
        if interaction == .launch {
            incoming ? playIncomingLaunchInteraction() : playLaunchPreview()
            return
        }
        if interaction == .bomb {
            playBombInteraction(incoming: incoming)
            return
        }
        if interaction == .vortex || interaction == .wave || interaction == .bubble {
            playMotionInteraction(interaction, incoming: incoming)
            return
        }
        let target = incoming || guestView.isHidden ? petView : guestView
        switch interaction {
        case .pet:
            playPetInteraction(target: target)
            return
        case .hug:
            playHugInteraction()
            return
        case .highFive:
            playHighFiveInteraction()
            return
        case .launch, .bomb, .vortex, .wave, .bubble:
            break
        }
        interactionTimer = Timer.scheduledTimer(withTimeInterval: 0.85, repeats: false) { [weak self] _ in
            self?.interactionPaused = false
            self?.interactionTimer = nil
        }
        RunLoop.main.add(interactionTimer!, forMode: .common)
    }

    private func playPetInteraction(target: PetView) {
        target.playFriendlyEffect()
        let center = target === petView
            ? NSPoint(x: petView.characterBounds.midX, y: petView.characterBounds.midY + 12)
            : NSPoint(
                x: guestView.frame.minX + guestView.characterBounds.midX,
                y: guestView.frame.minY + guestView.characterBounds.midY + 12
            )
        let effect = interactionEffectView(kind: .pet, size: NSSize(width: 125, height: 95))
        positionInteractionEffect(effect, center: center)
        let started = Date()
        let duration: TimeInterval = 1.15
        remoteInteractionTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / PetMotionTiming.framesPerSecond, repeats: true
        ) { [weak self, weak effect] timer in
            guard let self, let effect else { timer.invalidate(); return }
            let phase = min(1, CGFloat(Date().timeIntervalSince(started) / duration))
            effect.phase = phase
            if phase >= 1 {
                timer.invalidate()
                self.remoteInteractionTimer = nil
                self.finishRemoteInteraction()
            }
        }
        if let remoteInteractionTimer { RunLoop.main.add(remoteInteractionTimer, forMode: .common) }
    }

    private func playHighFiveInteraction() {
        let originalGuestFrame = guestView.frame
        if !guestView.isHidden { remoteInteractionGuestOriginalFrame = originalGuestFrame }
        petView.playFriendlyEffect()
        if !guestView.isHidden { guestView.playFriendlyEffect() }
        let ownerCenter = NSPoint(x: petView.characterBounds.midX, y: petView.characterBounds.midY)
        let guestCenter = guestView.isHidden ? NSPoint(
            x: petView.characterBounds.maxX - 12, y: ownerCenter.y
        ) : NSPoint(
            x: guestView.frame.minX + guestView.characterBounds.midX,
            y: guestView.frame.minY + guestView.characterBounds.midY
        )
        let impactCenter = NSPoint(
            x: (ownerCenter.x + guestCenter.x) / 2,
            y: (ownerCenter.y + guestCenter.y) / 2 + 4
        )
        let effect = interactionEffectView(kind: .highFive, size: NSSize(width: 105, height: 105))
        positionInteractionEffect(effect, center: impactCenter)
        let started = Date()
        let duration: TimeInterval = 1.05
        remoteInteractionTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / PetMotionTiming.framesPerSecond, repeats: true
        ) { [weak self, weak effect] timer in
            guard let self, let effect else { timer.invalidate(); return }
            let phase = min(1, CGFloat(Date().timeIntervalSince(started) / duration))
            effect.phase = phase
            if !self.guestView.isHidden {
                var frame = originalGuestFrame
                frame.origin.x -= sin(phase * .pi) * 18
                self.guestView.frame = frame
                self.syncSceneOverlay()
            }
            if phase >= 1 {
                timer.invalidate()
                self.remoteInteractionTimer = nil
                self.finishRemoteInteraction()
            }
        }
        if let remoteInteractionTimer { RunLoop.main.add(remoteInteractionTimer, forMode: .common) }
    }

    private func playHugInteraction() {
        let originalGuestFrame = guestView.frame
        if !guestView.isHidden { remoteInteractionGuestOriginalFrame = originalGuestFrame }
        petView.playHugEffect()
        if !guestView.isHidden { guestView.playHugEffect() }

        let ownerCenter = NSPoint(x: petView.characterBounds.midX, y: petView.characterBounds.midY)
        let guestCenter = guestView.isHidden ? ownerCenter : NSPoint(
            x: guestView.frame.minX + guestView.characterBounds.midX,
            y: guestView.frame.minY + guestView.characterBounds.midY
        )
        let heartCenter = NSPoint(
            x: (ownerCenter.x + guestCenter.x) / 2,
            y: max(ownerCenter.y, guestCenter.y) + 24
        )
        let hearts = interactionEffectView(kind: .hearts, size: NSSize(width: 150, height: 125))
        positionInteractionEffect(hearts, center: heartCenter)
        let started = Date()
        let duration: TimeInterval = 1.75
        remoteInteractionTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / PetMotionTiming.framesPerSecond, repeats: true
        ) { [weak self, weak hearts] timer in
            guard let self, let hearts else { timer.invalidate(); return }
            let phase = min(1, CGFloat(Date().timeIntervalSince(started) / duration))
            hearts.phase = phase
            if !self.guestView.isHidden {
                let approach = sin(phase * .pi) * 30
                var frame = originalGuestFrame
                frame.origin.x -= approach
                self.guestView.frame = frame
                self.syncSceneOverlay()
            }
            if phase >= 1 {
                timer.invalidate()
                self.remoteInteractionTimer = nil
                self.finishRemoteInteraction()
            }
        }
        if let remoteInteractionTimer { RunLoop.main.add(remoteInteractionTimer, forMode: .common) }
    }

    private func playIncomingLaunchInteraction() {
        flingVelocity = nil
        let original = panel.frame.origin
        remoteInteractionOriginalOrigin = original
        let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame
        let movementBounds = currentMovementBounds
        guard let visibleFrame,
              let allowed = PetMovementGeometry.allowedOrigins(
                visibleFrames: [visibleFrame],
                visualBounds: movementBounds,
                currentOrigin: original
              ) else {
            finishRemoteInteraction()
            return
        }
        let target = PetMovementGeometry.clamped(NSPoint(
            x: visibleFrame.midX - movementBounds.midX,
            y: visibleFrame.midY - movementBounds.midY
        ), to: allowed)
        petView.playClickEffect()
        let dizzyEffect = interactionEffectView(kind: .vortex, size: NSSize(width: 68, height: 68))
        positionInteractionEffect(dizzyEffect, center: NSPoint(
            x: petView.characterBounds.midX,
            y: petView.characterBounds.maxY - 6
        ))
        dizzyEffect.alphaValue = 0
        let started = Date()
        let duration: TimeInterval = 4.8
        remoteInteractionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / PetMotionTiming.framesPerSecond, repeats: true) { [weak self, weak dizzyEffect] timer in
            guard let self, let dizzyEffect else { timer.invalidate(); return }
            let phase = min(1, CGFloat(Date().timeIntervalSince(started) / duration))
            dizzyEffect.alphaValue = phase >= 0.35 && phase < 0.77 ? 1 : 0
            dizzyEffect.phase = (phase * 2.7).truncatingRemainder(dividingBy: 1)
            let origin = FishInteractionAnimationGeometry.launchOrigin(
                original: original,
                target: target,
                phase: phase,
                allowed: allowed
            )
            self.setPanelOriginIfChanged(origin)
            self.syncSceneOverlay()
            if phase >= 1 {
                timer.invalidate()
                self.remoteInteractionTimer = nil
                self.finishRemoteInteraction()
            }
        }
        if let remoteInteractionTimer { RunLoop.main.add(remoteInteractionTimer, forMode: .common) }
    }

    private func playLaunchPreview() {
        let source = NSPoint(x: petView.characterBounds.midX, y: petView.characterBounds.midY)
        let target = guestView.isHidden
            ? NSPoint(x: petView.characterBounds.maxX - 14, y: petView.characterBounds.midY)
            : NSPoint(
                x: guestView.frame.minX + guestView.characterBounds.midX,
                y: guestView.frame.minY + guestView.characterBounds.midY
            )
        let effect = interactionEffectView(kind: .launch, size: NSSize(width: 105, height: 85))
        let started = Date()
        let duration: TimeInterval = 1.25
        remoteInteractionTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / PetMotionTiming.framesPerSecond, repeats: true
        ) { [weak self, weak effect] timer in
            guard let self, let effect else { timer.invalidate(); return }
            let phase = min(1, CGFloat(Date().timeIntervalSince(started) / duration))
            effect.phase = phase
            let center = NSPoint(
                x: source.x + (target.x - source.x) * phase,
                y: source.y + (target.y - source.y) * phase + sin(phase * .pi) * 34
            )
            self.positionInteractionEffect(effect, center: center)
            if phase >= 1 {
                timer.invalidate()
                self.remoteInteractionTimer = nil
                (self.guestView.isHidden ? self.petView : self.guestView).playClickEffect()
                self.finishRemoteInteraction()
            }
        }
        if let remoteInteractionTimer { RunLoop.main.add(remoteInteractionTimer, forMode: .common) }
    }

    private func playBombInteraction(incoming: Bool) {
        let targetView = incoming || guestView.isHidden ? petView : guestView
        let target = targetView === petView
            ? NSPoint(x: petView.characterBounds.midX, y: petView.characterBounds.midY)
            : NSPoint(
                x: guestView.frame.minX + guestView.characterBounds.midX,
                y: guestView.frame.minY + guestView.characterBounds.midY
            )
        let source = incoming
            ? NSPoint(x: min(petView.bounds.maxX - 18, target.x + 120), y: min(petView.bounds.maxY - 24, target.y + 58))
            : NSPoint(x: petView.characterBounds.midX, y: petView.characterBounds.midY)
        let effect = interactionEffectView(kind: .bomb, size: NSSize(width: 150, height: 135))
        let started = Date()
        let duration: TimeInterval = 2.35
        var exploded = false
        remoteInteractionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / PetMotionTiming.framesPerSecond, repeats: true) { [weak self, weak effect] timer in
            guard let self, let effect else { timer.invalidate(); return }
            let phase = min(1, Date().timeIntervalSince(started) / duration)
            effect.phase = CGFloat(phase)
            if phase < 0.52 {
                let value = CGFloat(phase / 0.52)
                let eased = value * value * (3 - 2 * value)
                let point = NSPoint(
                    x: source.x + (target.x - source.x) * eased,
                    y: source.y + (target.y - source.y) * eased + sin(value * .pi) * 48
                )
                self.positionInteractionEffect(effect, center: point)
            } else if !exploded {
                exploded = true
                self.positionInteractionEffect(effect, center: target)
                targetView.playClickEffect()
            }
            if phase >= 1 {
                timer.invalidate()
                self.remoteInteractionTimer = nil
                self.finishRemoteInteraction()
            }
        }
        if let remoteInteractionTimer { RunLoop.main.add(remoteInteractionTimer, forMode: .common) }
    }

    private func playMotionInteraction(_ interaction: FishRemoteInteraction, incoming: Bool) {
        if !incoming, !guestView.isHidden {
            playGuestMotionPreview(interaction)
            return
        }

        flingVelocity = nil
        let original = panel.frame.origin
        remoteInteractionOriginalOrigin = original
        let movementBounds = currentMovementBounds
        guard let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame,
              let allowed = PetMovementGeometry.allowedOrigins(
                visibleFrames: [visibleFrame], visualBounds: movementBounds, currentOrigin: original
              ) else {
            finishRemoteInteraction()
            return
        }
        let center = PetMovementGeometry.clamped(NSPoint(
            x: visibleFrame.midX - movementBounds.midX,
            y: visibleFrame.midY - movementBounds.midY
        ), to: allowed)
        let opposite = PetMovementGeometry.clamped(NSPoint(
            x: allowed.minX + allowed.maxX - original.x,
            y: original.y
        ), to: allowed)
        let edgeX = abs(original.x - allowed.minX) < abs(original.x - allowed.maxX)
            ? allowed.minX : allowed.maxX
        let edge = NSPoint(x: edgeX, y: original.y)
        let kind: FishInteractionEffectView.Kind = interaction == .vortex
            ? .vortex : interaction == .wave ? .wave : .bubble
        let effect = interactionEffectView(
            kind: kind,
            size: interaction == .bubble
                ? NSSize(width: 155, height: 155)
                : NSSize(width: 150, height: 115)
        )
        positionInteractionEffect(effect, center: NSPoint(
            x: petView.characterBounds.midX,
            y: interaction == .wave ? petView.characterBounds.minY + 12 : petView.characterBounds.midY
        ))
        switch interaction {
        case .vortex: petView.playHugEffect()
        case .wave: petView.playBumpEffect()
        case .bubble: petView.playFriendlyEffect()
        default: break
        }
        let started = Date()
        let duration: TimeInterval = interaction == .vortex ? 2.5 : 2.8
        remoteInteractionTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / PetMotionTiming.framesPerSecond, repeats: true
        ) { [weak self, weak effect] timer in
            guard let self, let effect else { timer.invalidate(); return }
            let phase = min(1, CGFloat(Date().timeIntervalSince(started) / duration))
            effect.phase = phase
            let origin: NSPoint
            switch interaction {
            case .vortex:
                origin = FishInteractionAnimationGeometry.vortexOrigin(
                    original: original, center: center, opposite: opposite,
                    phase: phase, allowed: allowed
                )
                let hidden = phase > 0.39 && phase < 0.53
                self.petView.alphaValue = hidden ? 0.12 : 1
                self.guestView.alphaValue = hidden ? 0.12 : 1
            case .wave:
                origin = FishInteractionAnimationGeometry.waveOrigin(
                    original: original, edge: edge, phase: phase, allowed: allowed
                )
            case .bubble:
                origin = FishInteractionAnimationGeometry.bubbleOrigin(
                    original: original, center: center, phase: phase, allowed: allowed
                )
            default:
                origin = original
            }
            self.setPanelOriginIfChanged(origin)
            if phase >= 1 {
                timer.invalidate()
                self.remoteInteractionTimer = nil
                self.finishRemoteInteraction()
            }
        }
        if let remoteInteractionTimer { RunLoop.main.add(remoteInteractionTimer, forMode: .common) }
    }

    private func playGuestMotionPreview(_ interaction: FishRemoteInteraction) {
        let original = guestView.frame
        remoteInteractionGuestOriginalFrame = original
        switch interaction {
        case .vortex: guestView.playHugEffect()
        case .wave: guestView.playBumpEffect()
        case .bubble: guestView.playFriendlyEffect()
        default: break
        }
        let kind: FishInteractionEffectView.Kind = interaction == .vortex
            ? .vortex : interaction == .wave ? .wave : .bubble
        let effect = interactionEffectView(
            kind: kind,
            size: interaction == .bubble
                ? NSSize(width: 145, height: 145)
                : NSSize(width: 140, height: 105)
        )
        let started = Date()
        let duration: TimeInterval = 2.2
        remoteInteractionTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / PetMotionTiming.framesPerSecond, repeats: true
        ) { [weak self, weak effect] timer in
            guard let self, let effect else { timer.invalidate(); return }
            let phase = min(1, CGFloat(Date().timeIntervalSince(started) / duration))
            effect.phase = phase
            let envelope = sin(phase * .pi)
            var frame = original
            switch interaction {
            case .vortex:
                frame.origin.x += sin(phase * .pi * 6) * 14 * envelope
                frame.origin.y += cos(phase * .pi * 6) * 9 * envelope
                self.guestView.alphaValue = phase > 0.40 && phase < 0.58 ? 0.18 : 1
            case .wave:
                frame.origin.x += 52 * envelope
                frame.origin.y += sin(phase * .pi * 4) * 6
            case .bubble:
                frame.origin.x -= 38 * envelope
                frame.origin.y += 18 * envelope + sin(phase * .pi * 5) * 5
            default:
                break
            }
            self.guestView.frame = frame
            let target = NSPoint(
                x: frame.minX + self.guestView.characterBounds.midX,
                y: frame.minY + self.guestView.characterBounds.midY
            )
            self.positionInteractionEffect(effect, center: target)
            self.syncSceneOverlay()
            if phase >= 1 {
                timer.invalidate()
                self.remoteInteractionTimer = nil
                self.finishRemoteInteraction()
            }
        }
        if let remoteInteractionTimer { RunLoop.main.add(remoteInteractionTimer, forMode: .common) }
    }

    private func interactionEffectView(
        kind: FishInteractionEffectView.Kind,
        size: NSSize
    ) -> FishInteractionEffectView {
        let view = FishInteractionEffectView(kind: kind, frame: NSRect(origin: .zero, size: size))
        petView.addSubview(view, positioned: .above, relativeTo: guestView)
        remoteInteractionOverlays.append(view)
        return view
    }

    private func positionInteractionEffect(_ view: NSView, center: NSPoint) {
        view.frame.origin = NSPoint(x: center.x - view.frame.width / 2, y: center.y - view.frame.height / 2)
    }

    private func cancelRemoteInteraction(restorePosition: Bool) {
        remoteInteractionTimer?.invalidate()
        remoteInteractionTimer = nil
        remoteInteractionOverlays.forEach { $0.removeFromSuperview() }
        remoteInteractionOverlays.removeAll(keepingCapacity: true)
        petView.alphaValue = 1
        guestView.alphaValue = 1
        if let guestFrame = remoteInteractionGuestOriginalFrame {
            guestView.frame = guestFrame
            remoteInteractionGuestOriginalFrame = nil
            syncSceneOverlay()
        }
        if restorePosition, let original = remoteInteractionOriginalOrigin {
            setPanelOriginIfChanged(original)
            preciseOrigin = original
            bobBaselineY = original.y
            lastAutomaticOrigin = panel.frame.origin
            syncSceneOverlay()
        }
        remoteInteractionOriginalOrigin = nil
    }

    private func finishRemoteInteraction() {
        cancelRemoteInteraction(restorePosition: true)
        interactionPaused = false
        lastFrameUptime = ProcessInfo.processInfo.systemUptime
    }

    func setMenuPaused(_ paused: Bool) {
        menuPaused = paused
        if paused {
            flingVelocity = nil
            syncSceneOverlay()
        }
    }

    func setComposerPaused(_ paused: Bool) {
        composerPaused = paused
        if paused {
            flingVelocity = nil
            petView.updateMotion(elapsed: petView.motionElapsed, bobOffset: 0)
            guestView.updateMotion(elapsed: guestView.motionElapsed, bobOffset: 0)
            syncSceneOverlay()
        }
    }

    func setStatusAppearance(
        faceID: String?, accessoryID: String?, accessories: JSONValue?, customization: JSONValue?
    ) {
        statusFaceID = faceID
        petView.setMoodFace(faceID)
        var specification = CharacterAccessories(config.pet.accessories[config.pet.characterPackId])
        if let accessories {
            let override = CharacterAccessories(accessories)
            for (slot, id) in override.equipped { specification.equipped[slot] = id }
            for (id, tuning) in override.tuning { specification.tuning[id] = tuning }
        }
        if let accessoryID,
           let slot = petView.accessoryPacks.first(where: { $0.id == accessoryID })?.manifest.slot,
           slot != "face", slot != "clock", slot != "message-indicator" {
            specification.equipped[slot] = accessoryID
        }
        petView.accessorySpec = specification
        petView.customization = customization ?? config.pet.customization[config.pet.characterPackId]
    }

    func updateClock(state: ClockState, timerText: String?) {
        petView.alarmClockAccessoryID = state.preferences.effectiveAlarmAccessoryID
        petView.alarmClockVisible = ClockAccessoryPolicy.shouldShowClock(
            state: state,
            nowMs: Date().timeIntervalSince1970 * 1_000
        )
        petView.alarmRinging = state.alerts.contains(where: { $0.state == "ringing" })
        overlayView.clockAlert = state.alerts.first(where: { $0.state == "ringing" })
        overlayView.timerText = timerText
    }

    func setClockActions(snooze: @escaping (String) -> Void, dismiss: @escaping (String) -> Void) {
        overlayView.onClockSnooze = snooze
        overlayView.onClockDismiss = dismiss
    }

    func updatePerformance(_ sample: PerformanceSample?) { overlayView.performanceSample = sample }

    func updateUnreadCount(_ count: Int, indicatorID: String? = nil) {
        if let indicatorID {
            overlayView.messageIndicatorID = FishMessageIndicatorStyle.normalized(indicatorID)
        }
        overlayView.unreadMessageCount = count
    }

    func showFriendMessage(
        id: UUID,
        contactID: UUID? = nil,
        text: String,
        color: String?,
        speaker: PetMessageSpeaker,
        duration: TimeInterval
    ) {
        let now = Date()
        let expiresAt = now.addingTimeInterval(max(1, duration))
        let bubble = PetMessageBubble(
            id: id,
            contactID: contactID,
            text: text,
            color: color,
            speaker: speaker,
            expiresAt: expiresAt
        )
        overlayView.friendMessageBubbles = PetMessageBubbleStack.inserting(
            bubble,
            into: overlayView.friendMessageBubbles,
            now: now
        )
        beginSpeakingPresentation(for: speaker, text: text, now: now)
        scheduleFriendBubbleExpiry()
        show()
    }

    func showVisit(presence: FishPresence, friendName: String, runtime: AppRuntime) {
        let isBeginningVisit = guestView.isHidden || displayedVisitFriendName != friendName
        if !guestView.isHidden,
           displayedVisitPresence == presence,
           displayedVisitFriendName == friendName {
            return
        }
        guard let character = try? runtime.catalog?.character(id: presence.characterPackID) else { return }
        guestView.character = character
        guestView.characterScale = min(0.82, config.pet.scale * 0.82)
        guestView.accessoryPacks = runtime.accessories
        guestView.customization = presence.customization
        var guestAccessories = presence.statusAccessories.map(CharacterAccessories.init)
            ?? CharacterAccessories(presence.accessories)
        if let accessoryID = presence.statusAccessoryID,
           let slot = runtime.accessories.first(where: { $0.id == accessoryID })?.manifest.slot,
           slot != "face", slot != "clock", slot != "message-indicator" {
            guestAccessories.equipped[slot] = accessoryID
        }
        guestView.accessorySpec = guestAccessories
        guestView.setMoodFace(presence.statusFaceID ?? presence.status?.faceID)
        guestView.motionState = .idle
        guestView.updateMotion(elapsed: 0, bobOffset: 0)
        guestView.isHidden = false
        overlayView.visitingFriendName = friendName
        overlayView.visitingFriendStatus = presence.status
        if isBeginningVisit {
            overlayView.visitAnnouncementFriendName = friendName
            visitAnnouncementWorkItem?.cancel()
            let announcement = DispatchWorkItem { [weak self] in
                self?.overlayView.visitAnnouncementFriendName = nil
            }
            visitAnnouncementWorkItem = announcement
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: announcement)
        }
        displayedVisitPresence = presence
        displayedVisitFriendName = friendName
        syncSceneOverlay()
        preciseOrigin = nil
        bobBaselineY = nil
    }

    func endVisit() {
        visitAnnouncementWorkItem?.cancel()
        visitAnnouncementWorkItem = nil
        guestView.isHidden = true
        displayedVisitPresence = nil
        displayedVisitFriendName = nil
        overlayView.visitingFriendName = nil
        overlayView.visitingFriendStatus = nil
        overlayView.visitAnnouncementFriendName = nil
        overlayView.companionCharacterBounds = nil
        petView.companionCharacterBounds = nil
        overlayView.friendMessageBubbles.removeAll { $0.speaker == .visitor }
        clearSpeakingPresentation(for: .visitor)
        scheduleFriendBubbleExpiry()
        preciseOrigin = nil
        bobBaselineY = nil
        syncSceneOverlay()
    }

    func animateExit(completion: @escaping () -> Void) {
        movementDisplayLink.stop()
        let initialFrame = panel.frame
        let started = Date()
        var timer: Timer?
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / PetMotionTiming.framesPerSecond, repeats: true) { [weak self] value in
            guard let self else { value.invalidate(); completion(); return }
            let progress = min(1, Date().timeIntervalSince(started) / 0.75)
            self.panel.alphaValue = 1 - progress
            self.overlayPanel.alphaValue = 1 - progress
            self.panel.setFrameOrigin(NSPoint(x: initialFrame.minX, y: initialFrame.minY - progress * 18))
            self.syncSceneOverlay()
            if progress >= 1 {
                value.invalidate(); timer = nil; completion()
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func syncMovementTimer() {
        movementEnabled = ((hasActiveTasks && taskWantsMovement && config.pet.roamWhenTasks)
            || (!hasActiveTasks && config.pet.roamWhenNoTasks))
        if !hasActiveTasks { motionState = movementEnabled ? .roam : .idle }
        petView.motionState = motionState
        guard !movementDisplayLink.isRunning else { return }
        lastFrameUptime = ProcessInfo.processInfo.systemUptime
        movementDisplayLink.start()
    }

    private func moveOneFrame() {
        let visualBounds = currentMovementBounds
        let actualOrigin = panel.frame.origin
        guard let allowed = PetMovementGeometry.allowedOrigins(
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            visualBounds: visualBounds,
            currentOrigin: actualOrigin
        ) else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        let elapsed = uptime - (lastFrameUptime ?? uptime - 1.0 / PetMotionTiming.framesPerSecond)
        lastFrameUptime = uptime
        let step = PetMotionTiming.travelDistance(speed: config.pet.speed, elapsed: elapsed)
        let motionElapsed = uptime - motionStartUptime
        updatePointerInteraction()
        let movementPaused = PetMovementPause.shouldPause(
            hovering: hoverPaused,
            menuOpen: menuPaused,
            interacting: interactionPaused || composerPaused,
            dragging: dragging,
            flinging: flingVelocity != nil
        )
        bobElapsed = PetMotionTiming.advancedBobElapsed(
            current: bobElapsed,
            frameElapsed: elapsed,
            paused: movementPaused
        )
        bobVisibility = PetMotionTiming.transitionedBobVisibility(
            current: bobVisibility,
            frameElapsed: elapsed,
            paused: movementPaused
        )
        let bob = PetMotionTiming.swimOffset(
            elapsed: bobElapsed,
            characterID: petView.characterID,
            state: motionState
        ) * bobVisibility
        let externallyMoved = lastAutomaticOrigin.map {
            abs(actualOrigin.x - $0.x) > 1.5 || abs(actualOrigin.y - $0.y) > 1.5
        } ?? true
        if externallyMoved || preciseOrigin == nil {
            preciseOrigin = actualOrigin
            bobBaselineY = actualOrigin.y
        }
        var origin = preciseOrigin ?? actualOrigin
        petView.updateMotion(
            elapsed: motionElapsed,
            bobOffset: bob
        )
        if !guestView.isHidden {
            guestView.motionState = motionState
            guestView.updateMotion(elapsed: motionElapsed, bobOffset: bob)
        }
        syncSceneOverlay()

        if dragging { return }
        if movementPaused { return }
        if var velocity = flingVelocity {
            let intended = NSPoint(x: origin.x + velocity.dx * elapsed, y: origin.y + velocity.dy * elapsed)
            origin = PetMovementGeometry.clamped(intended, to: allowed)
            var bounced = false
            if abs(origin.x - intended.x) > 0.001 {
                velocity.dx = -velocity.dx * 0.72
                bounced = true
            }
            if abs(origin.y - intended.y) > 0.001 {
                velocity.dy = -velocity.dy * 0.72
                bounced = true
            }
            if bounced { petView.playBumpEffect() }
            let decay = pow(0.985, elapsed / 0.03)
            velocity.dx *= decay
            velocity.dy *= decay
            if hypot(velocity.dx, velocity.dy) < 16.67 {
                flingVelocity = nil
            } else {
                flingVelocity = velocity
            }
            if config.pet.flipOnBounce {
                petView.direction = velocity.dx >= 0 ? 1 : -1
                guestView.direction = petView.direction
            }
            setPanelOriginIfChanged(origin)
            preciseOrigin = origin
            // A fling is also a deliberate placement. Keep its latest height
            // as the horizontal-roaming baseline so the first frame after the
            // velocity stops cannot restore the pre-drag (usually bottom)
            // baseline and make the pet appear to teleport.
            bobBaselineY = origin.y
            lastAutomaticOrigin = panel.frame.origin
            return
        }

        if config.pet.moveAxis == "vertical", movementEnabled {
            origin.y += movementDirection * step
            if origin.y <= allowed.minY {
                origin.y = allowed.minY
                movementDirection = 1
                petView.playBumpEffect()
            } else if origin.y >= allowed.maxY {
                origin.y = allowed.maxY
                movementDirection = -1
                petView.playBumpEffect()
            }
            origin.x = min(max(origin.x, allowed.minX), allowed.maxX)
        } else {
            if movementEnabled, config.pet.moveAxis == "horizontal" {
                origin.x += movementDirection * step
                if origin.x <= allowed.minX {
                    origin.x = allowed.minX
                    movementDirection = 1
                    petView.playBumpEffect()
                } else if origin.x >= allowed.maxX {
                    origin.x = allowed.maxX
                    movementDirection = -1
                    petView.playBumpEffect()
                }
            }
            if bobBaselineY == nil { bobBaselineY = origin.y }
            origin.y = min(max(bobBaselineY ?? origin.y, allowed.minY), allowed.maxY)
            origin.x = min(max(origin.x, allowed.minX), allowed.maxX)
        }
        if config.pet.flipOnBounce {
            petView.direction = movementDirection
            guestView.direction = movementDirection
        }
        setPanelOriginIfChanged(origin)
        preciseOrigin = origin
        bobBaselineY = origin.y
        lastAutomaticOrigin = panel.frame.origin
    }

    private func beginDrag() {
        dragging = true
        hoverPaused = false
        flingVelocity = nil
        syncSceneOverlay()
        preciseOrigin = panel.frame.origin
        lastAutomaticOrigin = panel.frame.origin
    }

    private func dragBy(dx: CGFloat, dy: CGFloat) {
        guard dragging else { return }
        let visualBounds = currentMovementBounds
        let current = panel.frame.origin
        guard let allowed = PetMovementGeometry.allowedOrigins(
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            visualBounds: visualBounds,
            currentOrigin: current
        ) else { return }
        let origin = PetMovementGeometry.clamped(NSPoint(x: current.x + dx, y: current.y + dy), to: allowed)
        setPanelOriginIfChanged(origin)
        preciseOrigin = origin
        lastAutomaticOrigin = panel.frame.origin
    }

    private func endDrag(velocityX: CGFloat, velocityY: CGFloat) {
        dragging = false
        preciseOrigin = panel.frame.origin
        bobBaselineY = panel.frame.origin.y
        lastAutomaticOrigin = panel.frame.origin
        let amplified = CGVector(dx: velocityX * 1.35, dy: velocityY * 1.35)
        let speed = hypot(amplified.dx, amplified.dy)
        guard speed >= 466.67 else { flingVelocity = nil; return }
        if abs(amplified.dx) >= 1 {
            petView.direction = amplified.dx >= 0 ? 1 : -1
            guestView.direction = petView.direction
        }
        let maximum: CGFloat = 1_833.33
        if speed > maximum {
            let scale = maximum / speed
            flingVelocity = CGVector(dx: amplified.dx * scale, dy: amplified.dy * scale)
        } else {
            flingVelocity = amplified
        }
    }

    private func updatePointerInteraction() {
        let pointer = NSEvent.mouseLocation
        let point = panel.convertPoint(fromScreen: pointer)
        let overlayPoint = overlayPanel.convertPoint(fromScreen: pointer)
        let artworkHovering = petView.containsInteractivePoint(point) && !dragging
        let overlayHovering = overlayView.containsInteractivePoint(overlayPoint) && !dragging
        let shouldIgnoreMouse = !(artworkHovering || dragging)
        if panel.ignoresMouseEvents != shouldIgnoreMouse {
            panel.ignoresMouseEvents = shouldIgnoreMouse
        }
        let shouldIgnoreOverlay = !overlayHovering
        if overlayPanel.ignoresMouseEvents != shouldIgnoreOverlay {
            overlayPanel.ignoresMouseEvents = shouldIgnoreOverlay
        }
        hoverPaused = artworkHovering || overlayHovering
        guard artworkHovering else {
            lastPointerX = nil
            pettingHistory.removeAll(keepingCapacity: true)
            return
        }
        guard let previousX = lastPointerX else { lastPointerX = point.x; return }
        let dx = point.x - previousX
        lastPointerX = point.x
        guard abs(dx) >= 0.25 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        pettingHistory.append((now, dx))
        pettingHistory.removeAll { now - $0.time > 0.9 }
        guard now >= pettingCooldownUntil else { return }
        var reversals = 0
        var travel: CGFloat = 0
        var previousSign: CGFloat = 0
        for sample in pettingHistory {
            travel += abs(sample.dx)
            let sign: CGFloat = sample.dx >= 0 ? 1 : -1
            if previousSign != 0, sign != previousSign { reversals += 1 }
            previousSign = sign
        }
        guard reversals >= 3, travel >= 44 else { return }
        pettingCooldownUntil = now + 2.6
        pettingHistory.removeAll(keepingCapacity: true)
        pettingStreak = now - lastPettingAt <= 12 ? pettingStreak + 1 : 1
        lastPettingAt = now
        petView.showBlush(streak: pettingStreak)
        onPetting?(pettingStreak)
    }

    private func setPanelOriginIfChanged(_ origin: NSPoint) {
        let current = panel.frame.origin
        guard abs(current.x - origin.x) > 0.001 || abs(current.y - origin.y) > 0.001 else { return }
        panel.setFrameOrigin(origin)
        syncSceneOverlay()
    }

    private var currentMovementBounds: NSRect {
        PetFormationGeometry.movementBounds(
            primaryBounds: petView.movementBounds,
            companionFrame: guestView.isHidden ? nil : guestView.frame,
            companionBounds: guestView.isHidden ? nil : guestView.movementBounds
        )
    }

    private func syncSceneOverlay() {
        // Overlay cards follow the panel/formation, not the five-point artwork
        // bob. This preserves the previous stable-card behavior and avoids a
        // full visible-frame redraw on every idle display-link tick.
        let primary = petView.characterBounds.offsetBy(
            dx: panel.frame.minX,
            dy: panel.frame.minY
        )
        let companion: NSRect? = guestView.isHidden ? nil : guestView.characterBounds.offsetBy(
            dx: panel.frame.minX + guestView.frame.minX,
            dy: panel.frame.minY + guestView.frame.minY
        )
        let formation = companion.map { primary.union($0) } ?? primary
        guard let nextAnchor = PetAttachedWindowGeometry.anchor(
            primaryFrame: primary,
            formationFrame: formation,
            visibleFrames: NSScreen.screens.map(\.visibleFrame)
        ) else { return }
        let visibleFrame = nextAnchor.visibleFrame
        let sceneFrame = PetOverlayScreenGeometry.sceneFrame(
            around: formation,
            inside: visibleFrame
        )
        if overlayPanel.frame != sceneFrame {
            overlayPanel.setFrame(sceneFrame, display: false)
        }
        overlayView.sceneCharacterBounds = PetOverlayScreenGeometry.localRect(
            for: primary,
            visibleFrame: sceneFrame
        )
        overlayView.companionCharacterBounds = companion.map {
            PetOverlayScreenGeometry.localRect(for: $0, visibleFrame: sceneFrame)
        }
        petView.companionCharacterBounds = guestView.isHidden ? nil : guestView.characterBounds.offsetBy(
            dx: guestView.frame.minX,
            dy: guestView.frame.minY
        )
        if sceneAnchor != nextAnchor {
            sceneAnchor = nextAnchor
            onSceneAnchorChanged?(nextAnchor)
        }
    }

    private func scheduleFriendBubbleExpiry() {
        friendBubbleTimer?.invalidate()
        let now = Date()
        overlayView.friendMessageBubbles = PetMessageBubbleStack.active(
            overlayView.friendMessageBubbles,
            now: now
        )
        overlayView.refreshFriendMessagePresentation()
        guard let next = overlayView.friendMessageBubbles.map(\.expiresAt).min() else {
            friendBubbleTimer = nil
            return
        }
        let isFading = overlayView.friendMessageBubbles.contains {
            $0.expiresAt.timeIntervalSince(now) <= PetMessageBubbleStack.fadeOutDuration
        }
        let nextFadeStart = overlayView.friendMessageBubbles
            .map { $0.expiresAt.addingTimeInterval(-PetMessageBubbleStack.fadeOutDuration) }
            .min() ?? next
        let interval = isFading
            ? 1.0 / 30.0
            : max(0.05, nextFadeStart.timeIntervalSince(now))
        friendBubbleTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: false
        ) { [weak self] _ in
            self?.friendBubbleTimer = nil
            self?.scheduleFriendBubbleExpiry()
        }
        if let friendBubbleTimer { RunLoop.main.add(friendBubbleTimer, forMode: .common) }
    }

    private func beginSpeakingPresentation(
        for speaker: PetMessageSpeaker,
        text: String,
        now: Date
    ) {
        speakingTimers[speaker]?.invalidate()
        let presentation = PetSpeakingPresentationPolicy.starting(text: text, now: now)
        speakingPresentations[speaker] = presentation
        characterView(for: speaker).beginSpeakingPresentation(presentation)
        scheduleSpeakingExpiry(for: speaker, presentation: presentation)
    }

    private func scheduleSpeakingExpiry(
        for speaker: PetMessageSpeaker,
        presentation: PetSpeakingPresentation
    ) {
        speakingTimers[speaker]?.invalidate()
        let interval = max(0.05, presentation.expiresAt.timeIntervalSinceNow)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.finishSpeakingPresentation(for: speaker, token: presentation.token)
        }
        speakingTimers[speaker] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func finishSpeakingPresentation(for speaker: PetMessageSpeaker, token: UUID) {
        guard let current = speakingPresentations[speaker], current.token == token else { return }
        let now = Date()
        guard PetSpeakingPresentationPolicy.shouldEnd(current, token: token, now: now) else {
            scheduleSpeakingExpiry(for: speaker, presentation: current)
            return
        }
        speakingTimers[speaker]?.invalidate()
        speakingTimers[speaker] = nil
        speakingPresentations[speaker] = nil
        characterView(for: speaker).endSpeakingPresentation(token: token, now: now)
    }

    private func clearSpeakingPresentation(for speaker: PetMessageSpeaker) {
        speakingTimers[speaker]?.invalidate()
        speakingTimers[speaker] = nil
        speakingPresentations[speaker] = nil
        characterView(for: speaker).clearSpeakingPresentation()
    }

    private func characterView(for speaker: PetMessageSpeaker) -> PetView {
        speaker == .owner ? petView : guestView
    }
}
