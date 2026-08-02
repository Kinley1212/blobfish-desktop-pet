import AppKit

final class PetView: NSView {
    var snapshot: TaskSnapshot = .idle {
        didSet {
            syncSpinner()
            needsDisplay = true
        }
    }

    var direction: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    private var blinking = false
    private var blinkTimer: Timer?
    private var spinnerTimer: Timer?
    private var spinnerPhase: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        scheduleBlink()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        scheduleBlink()
    }

    deinit {
        blinkTimer?.invalidate()
        spinnerTimer?.invalidate()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawTaskBubble()
        drawBlobfish()
    }

    private func drawBlobfish() {
        let body = NSRect(x: 108, y: 14, width: 84, height: 70)
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 7
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor(calibratedRed: 0.90, green: 0.72, blue: 0.76, alpha: 1).setFill()
        NSBezierPath(ovalIn: body).fill()
        NSGraphicsContext.restoreGraphicsState()

        let finColor = NSColor(calibratedRed: 0.85, green: 0.60, blue: 0.68, alpha: 1)
        finColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 99, y: 31, width: 23, height: 18)).fill()
        NSBezierPath(ovalIn: NSRect(x: 180, y: 30, width: 22, height: 17)).fill()

        let noseX = direction >= 0 ? body.minX - 6 : body.maxX - 18
        NSColor(calibratedRed: 0.92, green: 0.76, blue: 0.80, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: noseX, y: 29, width: 24, height: 24)).fill()

        NSColor(calibratedWhite: 0.22, alpha: 1).setStroke()
        let eyeY: CGFloat = 58
        if blinking {
            for x in [CGFloat(130), CGFloat(166)] {
                let eye = NSBezierPath()
                eye.move(to: NSPoint(x: x - 3, y: eyeY))
                eye.line(to: NSPoint(x: x + 3, y: eyeY))
                eye.lineWidth = 2
                eye.stroke()
            }
        } else {
            NSColor(calibratedWhite: 0.20, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 126, y: eyeY - 4, width: 8, height: 8)).fill()
            NSBezierPath(ovalIn: NSRect(x: 162, y: eyeY - 4, width: 8, height: 8)).fill()
        }

        let mouth = NSBezierPath()
        mouth.move(to: NSPoint(x: 138, y: 37))
        mouth.curve(
            to: NSPoint(x: 162, y: 37),
            controlPoint1: NSPoint(x: 144, y: 31),
            controlPoint2: NSPoint(x: 156, y: 31)
        )
        mouth.lineWidth = 2.2
        mouth.lineCapStyle = .round
        mouth.stroke()
    }

    private func drawTaskBubble() {
        guard snapshot.state != .idle else { return }
        let bubbleRect = NSRect(x: 23, y: 101, width: 254, height: 43)
        NSColor.white.withAlphaComponent(0.96).setFill()
        let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 13, yRadius: 13)
        bubble.fill()
        NSColor(calibratedWhite: 0.45, alpha: 0.18).setStroke()
        bubble.lineWidth = 1
        bubble.stroke()

        drawStatusIcon(at: NSPoint(x: 42, y: 122))
        let title = snapshot.title ?? "任务"
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.24, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        (title as NSString).draw(in: NSRect(x: 56, y: 114, width: 188, height: 17), withAttributes: attributes)

        if snapshot.activeCount > 1 {
            let count = "+\(snapshot.activeCount - 1)" as NSString
            count.draw(
                at: NSPoint(x: 246, y: 115),
                withAttributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: NSColor(calibratedRed: 0.31, green: 0.43, blue: 0.44, alpha: 1),
                ]
            )
        }
    }

    private func drawStatusIcon(at center: NSPoint) {
        switch snapshot.state {
        case .running:
            NSColor(calibratedRed: 0.37, green: 0.57, blue: 0.58, alpha: 1).setStroke()
            let spinner = NSBezierPath()
            spinner.appendArc(withCenter: center, radius: 6, startAngle: spinnerPhase, endAngle: spinnerPhase + 270)
            spinner.lineWidth = 2
            spinner.lineCapStyle = .round
            spinner.stroke()
        case .waiting:
            NSColor(calibratedRed: 0.72, green: 0.53, blue: 0.28, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)).fill()
            drawSymbol("!", at: center)
        case .completed:
            NSColor(calibratedRed: 0.35, green: 0.60, blue: 0.41, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)).fill()
            drawSymbol("✓", at: center)
        case .failed:
            NSColor(calibratedRed: 0.70, green: 0.34, blue: 0.32, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)).fill()
            drawSymbol("×", at: center)
        case .idle:
            break
        }
    }

    private func drawSymbol(_ symbol: NSString, at center: NSPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let size = symbol.size(withAttributes: attributes)
        symbol.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
    }

    private func syncSpinner() {
        spinnerTimer?.invalidate()
        spinnerTimer = nil
        guard snapshot.state == .running else { return }
        spinnerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.spinnerPhase = (self.spinnerPhase - 24).truncatingRemainder(dividingBy: 360)
            self.needsDisplay = true
        }
        RunLoop.main.add(spinnerTimer!, forMode: .common)
    }

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 3.5...8.5), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.blinking = true
            self.needsDisplay = true
            self.blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: false) { [weak self] _ in
                self?.blinking = false
                self?.needsDisplay = true
                self?.scheduleBlink()
            }
        }
    }
}
