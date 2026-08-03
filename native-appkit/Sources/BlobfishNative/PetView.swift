import AppKit

enum PetVisualEffect: Equatable {
    case success
    case failed
    case waiting
    case hit
    case bump
}

struct PetEffectTransform: Equatable {
    let scaleX: CGFloat
    let scaleY: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
}

enum PetEffectGeometry {
    private struct Keyframe {
        let progress: CGFloat
        let transform: PetEffectTransform
    }

    static func transform(for effect: PetVisualEffect, progress: CGFloat) -> PetEffectTransform {
        let identity = PetEffectTransform(scaleX: 1, scaleY: 1, offsetX: 0, offsetY: 0)
        let frames: [Keyframe]
        switch effect {
        case .hit:
            frames = [
                Keyframe(progress: 0, transform: identity),
                Keyframe(progress: 0.20, transform: PetEffectTransform(scaleX: 1.30, scaleY: 0.65, offsetX: 0, offsetY: -10)),
                Keyframe(progress: 0.50, transform: PetEffectTransform(scaleX: 0.85, scaleY: 1.15, offsetX: 0, offsetY: 6)),
                Keyframe(progress: 0.75, transform: PetEffectTransform(scaleX: 1.05, scaleY: 0.95, offsetX: 0, offsetY: -2)),
                Keyframe(progress: 1, transform: identity),
            ]
        case .bump:
            frames = [
                Keyframe(progress: 0, transform: identity),
                Keyframe(progress: 0.30, transform: PetEffectTransform(scaleX: 1.38, scaleY: 0.60, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 0.55, transform: PetEffectTransform(scaleX: 0.85, scaleY: 1.18, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 0.75, transform: PetEffectTransform(scaleX: 1.08, scaleY: 0.94, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 1, transform: identity),
            ]
        case .success:
            frames = [
                Keyframe(progress: 0, transform: identity),
                Keyframe(progress: 0.28, transform: PetEffectTransform(scaleX: 1, scaleY: 0.94, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 0.58, transform: PetEffectTransform(scaleX: 1, scaleY: 1.06, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 1, transform: identity),
            ]
        case .failed:
            frames = [
                Keyframe(progress: 0, transform: identity),
                Keyframe(progress: 0.55, transform: PetEffectTransform(scaleX: 1, scaleY: 0.88, offsetX: 0, offsetY: -6)),
                Keyframe(progress: 1, transform: identity),
            ]
        case .waiting:
            frames = [
                Keyframe(progress: 0, transform: identity),
                Keyframe(progress: 0.5, transform: PetEffectTransform(scaleX: 1, scaleY: 1, offsetX: 0, offsetY: 2)),
                Keyframe(progress: 1, transform: identity),
            ]
        }
        let value = min(1, max(0, progress))
        guard let upperIndex = frames.indices.dropFirst().first(where: { value <= frames[$0].progress }) else {
            return frames.last?.transform ?? identity
        }
        let lower = frames[upperIndex - 1]
        let upper = frames[upperIndex]
        let span = max(0.0001, upper.progress - lower.progress)
        let local = (value - lower.progress) / span
        func mix(_ start: CGFloat, _ end: CGFloat) -> CGFloat { start + (end - start) * local }
        return PetEffectTransform(
            scaleX: mix(lower.transform.scaleX, upper.transform.scaleX),
            scaleY: mix(lower.transform.scaleY, upper.transform.scaleY),
            offsetX: mix(lower.transform.offsetX, upper.transform.offsetX),
            offsetY: mix(lower.transform.offsetY, upper.transform.offsetY)
        )
    }
}

struct TaskCarouselPlacement: Equatable {
    let depth: Int
    let horizontalOffset: CGFloat
    let downwardOffset: CGFloat
    let scale: CGFloat
    let opacity: CGFloat
}

enum TaskCarouselGeometry {
    static let placements = [
        TaskCarouselPlacement(depth: 0, horizontalOffset: 0, downwardOffset: 0, scale: 1, opacity: 1),
        TaskCarouselPlacement(depth: 1, horizontalOffset: 16, downwardOffset: 10, scale: 0.96, opacity: 0.82),
        TaskCarouselPlacement(depth: 2, horizontalOffset: -15, downwardOffset: 20, scale: 0.92, opacity: 0.60),
        TaskCarouselPlacement(depth: 3, horizontalOffset: 12, downwardOffset: 29, scale: 0.88, opacity: 0.40),
    ]

    static func visibleIndices(total: Int, frontIndex: Int) -> [(index: Int, placement: TaskCarouselPlacement)] {
        guard total > 0 else { return [] }
        let normalized = ((frontIndex % total) + total) % total
        return placements.prefix(min(total, placements.count)).map {
            ((normalized + $0.depth) % total, $0)
        }
    }

    static func interpolated(
        from: TaskCarouselPlacement,
        to: TaskCarouselPlacement,
        progress: CGFloat
    ) -> TaskCarouselPlacement {
        let value = min(1, max(0, progress))
        func mix(_ start: CGFloat, _ end: CGFloat) -> CGFloat { start + (end - start) * value }
        return TaskCarouselPlacement(
            depth: value < 0.5 ? from.depth : to.depth,
            horizontalOffset: mix(from.horizontalOffset, to.horizontalOffset),
            downwardOffset: mix(from.downwardOffset, to.downwardOffset),
            scale: mix(from.scale, to.scale),
            opacity: mix(from.opacity, to.opacity)
        )
    }
}

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
    var accessoryPacks: [AccessoryPack] = [] {
        didSet { rebuildAccessoryImages(); rebuildCharacterImage() }
    }
    var accessorySpec = CharacterAccessories(nil) {
        didSet { rebuildAccessoryImages(); rebuildCharacterImage() }
    }
    var customization: JSONValue? { didSet { rebuildCharacterImage() } }
    var alarmClockVisible = false { didSet { rebuildAccessoryImages() } }
    var alarmRinging = false { didSet { syncClockAnimation() } }
    var timerText: String? { didSet { needsDisplay = true } }
    var performanceSample: PerformanceSample? { didSet { needsDisplay = true } }
    var performancePetName = "水滴鱼" { didSet { needsDisplay = true } }
    var visualBobOffset: CGFloat = 0 { didSet { needsDisplay = true } }

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
    private var carouselAnimationTimer: Timer?
    private var carouselFromIndex: Int?
    private var carouselProgress: CGFloat = 1
    private var characterImage: NSImage?
    private var accessoryImages: [(AccessoryPack, NSImage)] = []
    private var effect: PetVisualEffect?
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
        carouselAnimationTimer?.invalidate()
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
        NSGraphicsContext.saveGraphicsState()
        let bobTransform = NSAffineTransform()
        bobTransform.translateX(by: 0, yBy: visualBobOffset)
        bobTransform.concat()
        guard let characterImage else {
            drawBlobfish()
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        if let effect {
            let geometry = PetEffectGeometry.transform(for: effect, progress: effectPhase)
            let transform = NSAffineTransform()
            transform.translateX(
                by: characterBounds.midX + geometry.offsetX,
                yBy: characterBounds.midY + geometry.offsetY
            )
            transform.scaleX(by: geometry.scaleX, yBy: geometry.scaleY)
            transform.translateX(by: -characterBounds.midX, yBy: -characterBounds.midY)
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
        let faceID = accessorySpec.equipped["face"]
        let hidesBaseEyes = accessoryPacks.first {
            $0.id == faceID && $0.manifest.slot == "face"
        }?.manifest.hidesEyes == true
        characterImage = character.flatMap {
            SVGAppearanceRenderer.image(
                character: $0,
                customization: customization,
                blinking: blinking,
                hidesBaseEyes: hidesBaseEyes
            )
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
        let rect = NSRect(x: 8, y: 5, width: 116, height: 42)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowColor = NSColor(calibratedRed: 0.15, green: 0.21, blue: 0.20, alpha: 0.10)
        shadow.set()
        NSColor(calibratedRed: 0.973, green: 0.984, blue: 0.980, alpha: 0.92).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedRed: 0.325, green: 0.412, blue: 0.408, alpha: 0.18).setStroke()
        path.lineWidth = 1
        path.stroke()

        let color = NSColor(calibratedRed: 0.325, green: 0.412, blue: 0.408, alpha: 1)
        let system = String(
            format: "CPU %.0f%% · RAM %.0f%%",
            sample.systemCPUPercent,
            sample.systemRAMPercent
        ) as NSString
        system.draw(
            at: NSPoint(x: rect.minX + 8, y: rect.minY + 23),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: color,
            ]
        )
        let app = String(format: "%@ %.0f MB", performancePetName, sample.appMemoryMB) as NSString
        app.draw(
            at: NSPoint(x: rect.minX + 8, y: rect.minY + 7),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: color,
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
        guard !cards.isEmpty else { return }
        let entries: [(index: Int, placement: TaskCarouselPlacement, showsPosition: Bool)]
        if let fromIndex = carouselFromIndex, carouselProgress < 1 {
            let from = Dictionary(uniqueKeysWithValues: TaskCarouselGeometry
                .visibleIndices(total: cards.count, frontIndex: fromIndex)
                .map { ($0.index, $0.placement) })
            let to = Dictionary(uniqueKeysWithValues: TaskCarouselGeometry
                .visibleIndices(total: cards.count, frontIndex: carouselIndex)
                .map { ($0.index, $0.placement) })
            entries = Set(from.keys).union(to.keys).map { index in
                let start = from[index] ?? hiddenPlacement(basedOn: to[index]!)
                let end = to[index] ?? hiddenPlacement(basedOn: from[index]!)
                return (
                    index,
                    TaskCarouselGeometry.interpolated(from: start, to: end, progress: carouselProgress),
                    index == carouselIndex && carouselProgress >= 0.5
                )
            }.sorted { $0.placement.downwardOffset > $1.placement.downwardOffset }
        } else {
            entries = TaskCarouselGeometry.visibleIndices(total: cards.count, frontIndex: carouselIndex)
                .reversed()
                .map { ($0.index, $0.placement, $0.index == carouselIndex) }
        }
        for entry in entries {
            drawTaskCard(
                cards[entry.index],
                placement: entry.placement,
                position: entry.index + 1,
                total: cards.count,
                showsPosition: entry.showsPosition
            )
        }
    }

    private func hiddenPlacement(basedOn placement: TaskCarouselPlacement) -> TaskCarouselPlacement {
        TaskCarouselPlacement(
            depth: placement.depth,
            horizontalOffset: placement.horizontalOffset,
            downwardOffset: placement.downwardOffset,
            scale: placement.scale,
            opacity: 0
        )
    }

    private func drawSpeechBubble() {
        guard let transientMessage else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1.5
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(calibratedRed: 0.18, green: 0.16, blue: 0.17, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        let measured = (transientMessage as NSString).boundingRect(
            with: NSSize(width: 244, height: 52),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let width = min(260, max(32, ceil(measured.width) + 16))
        let height = min(60, max(24, ceil(measured.height) + 8))
        let y = snapshot.state == .idle ? characterBounds.maxY + 8 : characterBounds.maxY + 76
        let rect = NSRect(x: bounds.midX - width / 2, y: y, width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
        shadow.set()
        NSColor.white.withAlphaComponent(0.98).setFill()
        let bubble = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        bubble.fill()
        NSGraphicsContext.restoreGraphicsState()
        (transientMessage as NSString).draw(
            in: rect.insetBy(dx: 8, dy: 4),
            withAttributes: attributes
        )
    }

    private func drawTaskCard(
        _ card: TaskCard,
        placement: TaskCarouselPlacement,
        position: Int,
        total: Int,
        showsPosition: Bool
    ) {
        let font = NSFont.systemFont(ofSize: 11, weight: placement.depth == 0 ? .semibold : .medium)
        let countWidth: CGFloat = showsPosition && total > 1 ? 34 : 0
        let measuredTitle = (card.title as NSString).size(withAttributes: [.font: font]).width
        let unscaledWidth = min(270, max(178, measuredTitle + 42 + countWidth))
        let width = unscaledWidth * placement.scale
        let height = 26 * placement.scale
        let frontY = characterBounds.maxY + 43
        let rect = NSRect(
            x: bounds.midX + placement.horizontalOffset - width / 2,
            y: frontY - placement.downwardOffset,
            width: width,
            height: height
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = placement.depth == 0 ? 7 : 4
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.16 * placement.opacity)
        shadow.set()
        NSColor.white.withAlphaComponent(0.96 * placement.opacity).setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedRed: 0.28, green: 0.36, blue: 0.37, alpha: 0.16 * placement.opacity).setStroke()
        path.lineWidth = 1
        path.stroke()

        let iconCenter = NSPoint(x: rect.minX + 15 * placement.scale, y: rect.midY)
        drawStatusIcon(state: card.state, at: iconCenter, alpha: placement.opacity)

        let titleRight = rect.maxX - 9 - countWidth * placement.scale
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (card.title as NSString).draw(
            in: NSRect(x: rect.minX + 27 * placement.scale, y: rect.midY - 7, width: max(20, titleRight - rect.minX - 27 * placement.scale), height: 15),
            withAttributes: [
                .font: font,
                .foregroundColor: NSColor(calibratedWhite: 0.22, alpha: placement.opacity),
                .paragraphStyle: paragraph,
            ]
        )

        if showsPosition, total > 1 {
            let pill = NSRect(x: rect.maxX - 37, y: rect.midY - 8, width: 29, height: 16)
            NSColor(calibratedRed: 0.89, green: 0.93, blue: 0.92, alpha: 1).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
            let count = "\(position)/\(total)" as NSString
            let countAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium),
                .foregroundColor: NSColor(calibratedRed: 0.31, green: 0.40, blue: 0.41, alpha: 1),
            ]
            let size = count.size(withAttributes: countAttributes)
            count.draw(at: NSPoint(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2), withAttributes: countAttributes)
        }
    }

    func playEffect(_ state: TaskDisplayState) {
        let visualEffect: PetVisualEffect
        let duration: TimeInterval
        switch state {
        case .completed: visualEffect = .success; duration = 0.7
        case .failed: visualEffect = .failed; duration = 0.9
        case .waiting: visualEffect = .waiting; duration = 0.6
        default: return
        }
        startEffect(visualEffect, duration: duration)
    }

    func playClickEffect() { startEffect(.hit, duration: 0.5) }

    func playBumpEffect() { startEffect(.bump, duration: 0.32) }

    private func startEffect(_ visualEffect: PetVisualEffect, duration: TimeInterval) {
        effectTimer?.invalidate()
        effect = visualEffect
        effectPhase = 0
        let started = Date()
        effectTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.effectPhase = CGFloat(Date().timeIntervalSince(started) / duration)
            if self.effectPhase >= 1 {
                timer.invalidate()
                self.effectTimer = nil
                self.effect = nil
            }
            self.needsDisplay = true
        }
        RunLoop.main.add(effectTimer!, forMode: .common)
    }

    private func drawStatusIcon(state: TaskDisplayState, at center: NSPoint, alpha: CGFloat) {
        switch state {
        case .running:
            NSColor(calibratedRed: 0.37, green: 0.57, blue: 0.58, alpha: alpha).setStroke()
            let spinner = NSBezierPath()
            spinner.appendArc(withCenter: center, radius: 6, startAngle: spinnerPhase, endAngle: spinnerPhase + 270)
            spinner.lineWidth = 2
            spinner.lineCapStyle = .round
            spinner.stroke()
        case .waiting:
            NSColor(calibratedRed: 0.72, green: 0.53, blue: 0.28, alpha: alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)).fill()
            drawSymbol("…", at: center, alpha: alpha)
        case .completed:
            NSColor(calibratedRed: 0.35, green: 0.60, blue: 0.41, alpha: alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)).fill()
            drawSymbol("✓", at: center, alpha: alpha)
        case .failed:
            NSColor(calibratedRed: 0.70, green: 0.34, blue: 0.32, alpha: alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)).fill()
            drawSymbol("!", at: center, alpha: alpha)
        case .idle:
            break
        }
    }

    private func drawSymbol(_ symbol: NSString, at center: NSPoint, alpha: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
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
        let newTasks = snapshot.tasks
        guard newTasks != previous.tasks else { return }
        carouselTimer?.invalidate()
        carouselTimer = nil
        if let changed = newTasks.firstIndex(where: { card in
            guard let old = previous.tasks.first(where: { $0.id == card.id }) else { return true }
            return old.state != card.state || old.timestamp != card.timestamp
        }) {
            setCarouselIndex(changed, animated: previous.tasks.count > 1 && newTasks.count > 1)
        } else if carouselIndex >= newTasks.count {
            setCarouselIndex(0, animated: false)
        }
        guard newTasks.count > 1 else { return }
        carouselTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, !self.snapshot.tasks.isEmpty else { return }
            self.setCarouselIndex((self.carouselIndex + 1) % self.snapshot.tasks.count, animated: true)
        }
        RunLoop.main.add(carouselTimer!, forMode: .common)
    }

    private func setCarouselIndex(_ index: Int, animated: Bool) {
        guard index != carouselIndex else { return }
        carouselAnimationTimer?.invalidate()
        carouselAnimationTimer = nil
        let oldIndex = carouselIndex
        carouselIndex = index
        guard animated else {
            carouselFromIndex = nil
            carouselProgress = 1
            needsDisplay = true
            return
        }
        carouselFromIndex = oldIndex
        carouselProgress = 0
        let started = Date()
        carouselAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.carouselProgress = min(1, CGFloat(Date().timeIntervalSince(started) / 0.36))
            if self.carouselProgress >= 1 {
                timer.invalidate()
                self.carouselAnimationTimer = nil
                self.carouselFromIndex = nil
            }
            self.needsDisplay = true
        }
        RunLoop.main.add(carouselAnimationTimer!, forMode: .common)
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
