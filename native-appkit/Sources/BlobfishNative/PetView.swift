import AppKit

final class PetView: NSView {
    var onClick: (() -> Void)?
    var transientMessage: String? { didSet { needsDisplay = true } }
    var character: CharacterPack? {
        didSet {
            rebuildCharacterImage()
            needsDisplay = true
        }
    }

    var characterScale: Double = 1 { didSet { needsDisplay = true } }
    var accessoryPacks: [AccessoryPack] = [] { didSet { rebuildAccessoryImages() } }
    var accessorySpec = CharacterAccessories(nil) { didSet { rebuildAccessoryImages() } }
    var customization: JSONValue? { didSet { rebuildCharacterImage() } }
    var alarmClockVisible = false { didSet { rebuildAccessoryImages() } }
    var alarmRinging = false { didSet { syncClockAnimation() } }
    var timerText: String? { didSet { needsDisplay = true } }
    var performanceSample: PerformanceSample? { didSet { needsDisplay = true } }

    var characterBounds: NSRect {
        let size = character?.manifest.size ?? CharacterPack.Size(width: 105, height: 90)
        let scaled = NSSize(width: size.width * characterScale, height: size.height * characterScale)
        return NSRect(x: bounds.midX - scaled.width / 2, y: timerText == nil ? 4 : 24, width: scaled.width, height: scaled.height)
    }
    var movementBounds: NSRect {
        let art = characterBounds
        return NSRect(x: art.minX, y: art.minY, width: art.width, height: art.height + Self.bobDistance)
    }
    var snapshot: TaskSnapshot = .idle {
        didSet {
            syncCarousel(previous: oldValue)
            syncSpinner()
            needsDisplay = true
        }
    }

    var direction: CGFloat = 1 {
        didSet {
            if oldValue != direction { needsDisplay = true }
        }
    }

    private var blinking = false
    private static let bobDistance: CGFloat = 5
    private var blinkTimer: Timer?
    private var spinnerTimer: Timer?
    private var spinnerPhase: CGFloat = 0
    private var carouselIndex = 0
    private var carouselTimer: Timer?
    private var characterImage: NSImage?
    private var accessoryImages: [(AccessoryPack, NSImage)] = []
    private var effect: TaskDisplayState?
    private var effectPhase: CGFloat = 0
    private var effectTimer: Timer?
    private var clockAnimationTimer: Timer?
    private var clockShakePhase: CGFloat = 0

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
        carouselTimer?.invalidate()
        effectTimer?.invalidate()
        clockAnimationTimer?.invalidate()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawSpeechBubble()
        drawTaskBubble()
        drawTimerDisplay()
        drawPerformancePanel()
        drawCharacter()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
        super.mouseDown(with: event)
    }

    private func drawCharacter() {
        guard let characterImage else { drawBlobfish(); return }
        NSGraphicsContext.saveGraphicsState()
        if let effect {
            let transform = NSAffineTransform()
            switch effect {
            case .completed:
                let scale = 1 + sin(effectPhase * .pi) * 0.13
                transform.translateX(by: bounds.midX, yBy: characterBounds.midY)
                transform.scale(by: scale)
                transform.translateX(by: -bounds.midX, yBy: -characterBounds.midY)
            case .failed:
                transform.translateX(by: sin(effectPhase * .pi * 8) * 5, yBy: 0)
            case .waiting:
                transform.translateX(by: 0, yBy: sin(effectPhase * .pi * 4) * 2)
            default: break
            }
            transform.concat()
        }
        if direction < 0 {
            let transform = NSAffineTransform()
            transform.translateX(by: bounds.midX * 2, yBy: 0)
            transform.scaleX(by: -1, yBy: 1)
            transform.concat()
        }
        characterImage.draw(in: characterBounds, from: .zero, operation: .sourceOver, fraction: 1)
        drawAccessories()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func rebuildAccessoryImages() {
        let byID = Dictionary(uniqueKeysWithValues: accessoryPacks.map { ($0.id, $0) })
        var ids = Array(accessorySpec.equipped.values)
        if alarmClockVisible, !ids.contains("alarm-clock") { ids.append("alarm-clock") }
        accessoryImages = ids.compactMap { id in
            guard let pack = byID[id], let image = NSImage(contentsOf: pack.artURL) else { return nil }
            return (pack, image)
        }
        needsDisplay = true
    }

    private func rebuildCharacterImage() {
        characterImage = character.flatMap {
            SVGAppearanceRenderer.image(character: $0, customization: customization, blinking: blinking)
        }
        needsDisplay = true
    }

    private func drawAccessories() {
        guard let character, let sourceSize = characterImage?.size,
              sourceSize.width > 0, sourceSize.height > 0 else { return }
        let target = characterBounds
        let scaleX = target.width / sourceSize.width
        let scaleY = target.height / sourceSize.height
        for (pack, image) in accessoryImages {
            guard let slot = character.manifest.accessories?.slots[pack.manifest.slot] else { continue }
            let tuning = accessorySpec.tuning[pack.id] ?? AccessoryTuning(nil)
            let unitX = scaleX * slot.scale * tuning.size * tuning.width
            let unitY = scaleY * slot.scale * tuning.size * tuning.height
            let targetX = target.minX + (slot.x + tuning.offsetX) * scaleX
            let targetY = target.maxY - (slot.y + tuning.offsetY) * scaleY
            let imageSize = image.size
            let shake = alarmRinging && pack.id == "alarm-clock" ? sin(clockShakePhase) * 3 : 0
            let rect = NSRect(
                x: targetX - pack.manifest.anchor.x * unitX + shake,
                y: targetY - (imageSize.height - pack.manifest.anchor.y) * unitY,
                width: imageSize.width * unitX,
                height: imageSize.height * unitY
            )
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    private func drawTimerDisplay() {
        guard let timerText else { return }
        let rect = NSRect(x: bounds.midX - 40, y: 1, width: 80, height: 25)
        NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.94, alpha: 0.98).setFill()
        let calendar = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        calendar.fill()
        NSColor(calibratedRed: 0.34, green: 0.50, blue: 0.49, alpha: 1).setFill()
        NSRect(x: rect.minX, y: rect.maxY - 6, width: rect.width, height: 6).fill()
        let value = timerText as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.23, alpha: 1),
        ]
        let size = value.size(withAttributes: attributes)
        value.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.minY + 3), withAttributes: attributes)
    }

    private func drawPerformancePanel() {
        guard let sample = performanceSample else { return }
        let rect = NSRect(x: 205, y: 5, width: 88, height: 32)
        NSColor(calibratedWhite: 0.12, alpha: 0.76).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        let text = String(format: "CPU %2.0f%%\nRAM %2.0f%%", sample.systemCPUPercent, sample.systemRAMPercent) as NSString
        text.draw(
            in: NSRect(x: rect.minX + 8, y: rect.minY + 5, width: rect.width - 12, height: rect.height - 7),
            withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
        )
    }

    private func syncClockAnimation() {
        clockAnimationTimer?.invalidate(); clockAnimationTimer = nil
        guard alarmRinging else { clockShakePhase = 0; needsDisplay = true; return }
        clockAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.clockShakePhase += 1.2
            self.needsDisplay = true
        }
        RunLoop.main.add(clockAnimationTimer!, forMode: .common)
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
        let cards = snapshot.tasks
        if cards.count > 1 {
            for depth in stride(from: min(cards.count - 1, 2), through: 1, by: -1) {
                let rect = NSRect(x: 23 + CGFloat(depth) * 5, y: 137 - CGFloat(depth) * 7, width: 254 - CGFloat(depth) * 10, height: 43)
                NSColor.white.withAlphaComponent(0.28 + CGFloat(2 - depth) * 0.12).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13).fill()
            }
        }
        let bubbleRect = NSRect(x: 23, y: 137, width: 254, height: 43)
        NSColor.white.withAlphaComponent(0.96).setFill()
        let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 13, yRadius: 13)
        bubble.fill()
        NSColor(calibratedWhite: 0.45, alpha: 0.18).setStroke()
        bubble.lineWidth = 1
        bubble.stroke()

        drawStatusIcon(at: NSPoint(x: 42, y: 158))
        let currentCard = cards.indices.contains(carouselIndex) ? cards[carouselIndex] : nil
        let title = currentCard?.title ?? snapshot.title ?? "任务"
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.24, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        (title as NSString).draw(
            in: NSRect(x: 56, y: 150, width: 188, height: 17),
            withAttributes: attributes
        )

        if cards.count > 1 {
            let count = "\(carouselIndex + 1)/\(cards.count)" as NSString
            count.draw(
                at: NSPoint(x: 246, y: 151),
                withAttributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: NSColor(calibratedRed: 0.31, green: 0.43, blue: 0.44, alpha: 1),
                ]
            )
        }
    }

    private func drawSpeechBubble() {
        guard let transientMessage else { return }
        let rect = NSRect(x: 23, y: 88, width: 254, height: 40)
        NSColor.white.withAlphaComponent(0.96).setFill()
        let bubble = NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13)
        bubble.fill()
        NSColor(calibratedWhite: 0.45, alpha: 0.18).setStroke()
        bubble.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (transientMessage as NSString).draw(
            in: NSRect(x: 38, y: 100, width: 224, height: 17),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.24, alpha: 1),
                .paragraphStyle: paragraph,
            ]
        )
    }

    func playEffect(_ state: TaskDisplayState) {
        effectTimer?.invalidate()
        effect = state
        effectPhase = 0
        let started = Date()
        effectTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.effectPhase = CGFloat(Date().timeIntervalSince(started) / 1.1)
            if self.effectPhase >= 1 {
                timer.invalidate()
                self.effectTimer = nil
                self.effect = nil
            }
            self.needsDisplay = true
        }
        RunLoop.main.add(effectTimer!, forMode: .common)
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

    private func syncCarousel(previous: TaskSnapshot) {
        carouselTimer?.invalidate()
        carouselTimer = nil
        let newTasks = snapshot.tasks
        if let changed = newTasks.firstIndex(where: { card in
            guard let old = previous.tasks.first(where: { $0.id == card.id }) else { return true }
            return old.state != card.state || old.timestamp != card.timestamp
        }) {
            carouselIndex = changed
        } else if carouselIndex >= newTasks.count {
            carouselIndex = 0
        }
        guard newTasks.count > 1 else { return }
        carouselTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, !self.snapshot.tasks.isEmpty else { return }
            self.carouselIndex = (self.carouselIndex + 1) % self.snapshot.tasks.count
            self.needsDisplay = true
        }
        RunLoop.main.add(carouselTimer!, forMode: .common)
    }

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 3.5...8.5), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.blinking = true
            self.rebuildCharacterImage()
            self.needsDisplay = true
            self.blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: false) { [weak self] _ in
                self?.blinking = false
                self?.rebuildCharacterImage()
                self?.needsDisplay = true
                self?.scheduleBlink()
            }
        }
    }
}
