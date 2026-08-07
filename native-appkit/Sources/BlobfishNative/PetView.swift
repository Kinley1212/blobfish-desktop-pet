import AppKit
import QuartzCore

enum PetVisualEffect: Equatable {
    case success
    case failed
    case waiting
    case hit
    case bump
}

enum PetShadowStyle {
    static let offsetY: CGFloat = -3
    static let blurRadius: CGFloat = 3
    static let opacity: CGFloat = 0.15
    static let bottomInset: CGFloat = 10
}

struct PetBlushStyle: Equatable {
    let cheekRects: [CGRect]
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let centerAlpha: CGFloat
}

enum PetBlushGeometry {
    static func style(level: Int, characterID: String?, in bounds: CGRect) -> PetBlushStyle? {
        guard level > 0 else { return nil }
        let deep = level > 1
        let width = bounds.width * (deep ? 0.22 : 0.18)
        let height = bounds.height * (deep ? 0.14 : 0.12)
        let isWotou = characterID == "blobfish-wotou"
        let horizontalInset = bounds.width * (isWotou ? 0.18 : 0.12)
        let bottomInset = bounds.height * (isWotou ? 0.32 : 0.42)
        let left = CGRect(
            x: bounds.minX + horizontalInset,
            y: bounds.minY + bottomInset,
            width: width,
            height: height
        )
        let right = CGRect(
            x: bounds.maxX - horizontalInset - width,
            y: left.minY,
            width: width,
            height: height
        )
        return PetBlushStyle(
            cheekRects: [left, right],
            red: 1,
            green: deep ? 96 / 255 : 122 / 255,
            blue: deep ? 126 / 255 : 146 / 255,
            centerAlpha: deep ? 0.92 : 0.78
        )
    }
}

enum PerformancePanelGeometry {
    static let margin: CGFloat = 8

    static func size(for characterBounds: CGRect) -> CGSize {
        let height = characterBounds.height
        return CGSize(width: max(46, height * 0.64), height: height)
    }
}

enum PerformancePanelAnimation {
    static let duration: TimeInterval = 0.72

    static func progress(elapsed: TimeInterval, delay: TimeInterval) -> CGFloat {
        let span = max(0.001, duration - delay)
        let value = min(1, max(0, (elapsed - delay) / span))
        let eased = 1 - pow(1 - value, 3)
        let softBounce = sin(value * .pi * 3) * (1 - value) * 0.045
        return CGFloat(min(1, max(0, eased + softBounce)))
    }

    static func interpolate(_ from: Double, _ to: Double, progress: CGFloat) -> Double {
        from + (to - from) * Double(progress)
    }

    static func nested(total: Double, app: Double) -> (total: Double, app: Double) {
        let appValue = min(100, max(0, app))
        return (max(min(100, max(0, total)), appValue), appValue)
    }
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

    static func transform(for effect: PetVisualEffect, progress: CGFloat, characterID: String = "blobfish") -> PetEffectTransform {
        let identity = PetEffectTransform(scaleX: 1, scaleY: 1, offsetX: 0, offsetY: 0)
        let frames: [Keyframe]
        switch effect {
        case .hit:
            frames = characterID == "grass-buddy" ? [
                Keyframe(progress: 0, transform: identity),
                Keyframe(progress: 0.22, transform: PetEffectTransform(scaleX: 1.18, scaleY: 0.78, offsetX: 0, offsetY: -7)),
                Keyframe(progress: 0.52, transform: PetEffectTransform(scaleX: 0.92, scaleY: 1.10, offsetX: 0, offsetY: 5)),
                Keyframe(progress: 0.76, transform: PetEffectTransform(scaleX: 1.04, scaleY: 0.97, offsetX: 0, offsetY: -1)),
                Keyframe(progress: 1, transform: identity),
            ] : [
                Keyframe(progress: 0, transform: identity),
                Keyframe(progress: 0.20, transform: PetEffectTransform(scaleX: 1.30, scaleY: 0.65, offsetX: 0, offsetY: -10)),
                Keyframe(progress: 0.50, transform: PetEffectTransform(scaleX: 0.85, scaleY: 1.15, offsetX: 0, offsetY: 6)),
                Keyframe(progress: 0.75, transform: PetEffectTransform(scaleX: 1.05, scaleY: 0.95, offsetX: 0, offsetY: -2)),
                Keyframe(progress: 1, transform: identity),
            ]
        case .bump:
            frames = characterID == "grass-buddy" ? [
                Keyframe(progress: 0, transform: identity),
                Keyframe(progress: 0.28, transform: PetEffectTransform(scaleX: 1.24, scaleY: 0.72, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 0.58, transform: PetEffectTransform(scaleX: 0.91, scaleY: 1.10, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 0.78, transform: PetEffectTransform(scaleX: 1.04, scaleY: 0.97, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 1, transform: identity),
            ] : [
                Keyframe(progress: 0, transform: identity),
                Keyframe(progress: 0.30, transform: PetEffectTransform(scaleX: 1.38, scaleY: 0.60, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 0.55, transform: PetEffectTransform(scaleX: 0.85, scaleY: 1.18, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 0.75, transform: PetEffectTransform(scaleX: 1.08, scaleY: 0.94, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 1, transform: identity),
            ]
        case .success:
            frames = characterID == "grass-buddy" ? [
                Keyframe(progress: 0, transform: identity),
                Keyframe(progress: 0.20, transform: PetEffectTransform(scaleX: 1, scaleY: 0.94, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 0.52, transform: PetEffectTransform(scaleX: 1, scaleY: 1.04, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 0.76, transform: PetEffectTransform(scaleX: 1, scaleY: 0.98, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 1, transform: identity),
            ] : [
                Keyframe(progress: 0, transform: identity),
                Keyframe(progress: 0.28, transform: PetEffectTransform(scaleX: 1, scaleY: 0.94, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 0.58, transform: PetEffectTransform(scaleX: 1, scaleY: 1.06, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 0.78, transform: PetEffectTransform(scaleX: 1, scaleY: 0.98, offsetX: 0, offsetY: 0)),
                Keyframe(progress: 1, transform: identity),
            ]
        case .failed:
            frames = [
                Keyframe(progress: 0, transform: identity),
                Keyframe(progress: 0.55, transform: PetEffectTransform(scaleX: 1, scaleY: 0.88, offsetX: 0, offsetY: characterID == "grass-buddy" ? -7 : -6)),
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

    static func transitionProgress(_ progress: CGFloat) -> CGFloat {
        CGFloat(PetMotionTiming.cubicBezier(
            Double(progress),
            x1: 0.22, y1: 0.8,
            x2: 0.26, y2: 1
        ))
    }
}

enum TaskSpinnerTimeline {
    static let revolutionDuration: TimeInterval = 0.8

    static func start(
        current: TimeInterval?,
        hasRunningTask: Bool,
        now: TimeInterval
    ) -> TimeInterval? {
        guard hasRunningTask else { return nil }
        return current ?? now
    }

    static func angle(start: TimeInterval, now: TimeInterval) -> CGFloat {
        let elapsed = max(0, now - start)
        let phase = elapsed.truncatingRemainder(dividingBy: revolutionDuration) / revolutionDuration
        return 90 - CGFloat(phase * 360)
    }
}

enum ExpressionCanvasGeometry {
    static func targetAnchor(
        slotX: CGFloat,
        slotY: CGFloat,
        canvas: CGRect,
        target: CGRect
    ) -> CGPoint {
        guard canvas.width > 0, canvas.height > 0 else {
            return CGPoint(x: target.midX, y: target.midY)
        }
        return CGPoint(
            x: target.minX + (slotX - canvas.minX) * target.width / canvas.width,
            y: target.maxY - (slotY - canvas.minY) * target.height / canvas.height
        )
    }
}

enum ClockAccessoryPositionGeometry {
    static func centeredRect(
        offsetX: CGFloat,
        offsetY: CGFloat,
        canvas: CGRect,
        characterBounds: CGRect,
        containerBounds: CGRect,
        renderedSize: CGSize
    ) -> CGRect {
        guard canvas.width > 0, canvas.height > 0,
              characterBounds.width > 0, characterBounds.height > 0 else {
            return CGRect(
                x: containerBounds.midX - renderedSize.width / 2,
                y: containerBounds.midY - renderedSize.height / 2,
                width: renderedSize.width,
                height: renderedSize.height
            )
        }
        let scaleX = characterBounds.width / canvas.width
        let scaleY = characterBounds.height / canvas.height
        let halfWidth = renderedSize.width / 2
        let halfHeight = renderedSize.height / 2
        let allowedX = centerRange(
            minimum: containerBounds.minX,
            maximum: containerBounds.maxX,
            halfExtent: halfWidth
        )
        let allowedY = centerRange(
            minimum: containerBounds.minY,
            maximum: containerBounds.maxY,
            halfExtent: halfHeight
        )
        let requestedX = characterBounds.midX + offsetX * scaleX
        let requestedY = characterBounds.midY - offsetY * scaleY
        let centerX = min(allowedX.upperBound, max(allowedX.lowerBound, requestedX))
        let centerY = min(allowedY.upperBound, max(allowedY.lowerBound, requestedY))
        return CGRect(
            x: centerX - halfWidth,
            y: centerY - halfHeight,
            width: renderedSize.width,
            height: renderedSize.height
        )
    }

    private static func centerRange(
        minimum: CGFloat,
        maximum: CGFloat,
        halfExtent: CGFloat
    ) -> ClosedRange<CGFloat> {
        let lower = minimum + halfExtent
        let upper = maximum - halfExtent
        guard lower <= upper else {
            let center = (minimum + maximum) / 2
            return center...center
        }
        return lower...upper
    }
}

enum PetViewContentMode {
    case artwork
    case overlay
    case combined

    var drawsArtwork: Bool { self != .overlay }
    var drawsOverlay: Bool { self != .artwork }
}

enum PetPrimaryClickIntent: Equatable {
    case singleClick
    case doubleClick
    case drag
}

enum PetPrimaryClickIntentPolicy {
    static let dragThreshold: CGFloat = 4

    static func resolve(dragDistance: CGFloat, clickCount: Int) -> PetPrimaryClickIntent {
        if dragDistance >= dragThreshold { return .drag }
        if clickCount == 2 { return .doubleClick }
        return .singleClick
    }

    static func cancelsPendingSingle(_ intent: PetPrimaryClickIntent) -> Bool {
        intent != .singleClick
    }
}

final class PetView: NSView, CALayerDelegate {
    private let contentMode: PetViewContentMode
    var ignoresMouseInteraction = false
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onRightDoubleClick: (() -> Void)?
    var onSpeechBubbleClick: ((UUID?) -> Void)?
    var onUnreadBadgeClick: (() -> Void)?
    var onCompanionClick: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDragMove: ((CGFloat, CGFloat) -> Void)?
    var onDragEnd: ((CGFloat, CGFloat) -> Void)?
    var onClockSnooze: ((String) -> Void)?
    var onClockDismiss: ((String) -> Void)?
    var transientMessage: String? { didSet { invalidateOverlay() } }
    var transientMessageEvent: String? { didSet { invalidateOverlay() } }
    var transientMessageColor: String? { didSet { invalidateOverlay() } }
    var unreadMessageCount = 0 { didSet { if oldValue != unreadMessageCount { invalidateOverlay() } } }
    var messageIndicatorID = FishMessageIndicatorStyle.defaultID {
        didSet {
            let normalized = FishMessageIndicatorStyle.normalized(messageIndicatorID)
            if normalized != messageIndicatorID { messageIndicatorID = normalized; return }
            guard oldValue != messageIndicatorID else { return }
            rebuildMessageIndicatorImage()
            invalidateOverlay()
        }
    }
    var visitingFriendName: String? { didSet { if oldValue != visitingFriendName { invalidateOverlay() } } }
    var visitingFriendStatus: FishUserStatus? { didSet { if oldValue != visitingFriendStatus { invalidateOverlay() } } }
    var visitAnnouncementFriendName: String? {
        didSet { if oldValue != visitAnnouncementFriendName { invalidateOverlay() } }
    }
    var companionCharacterBounds: NSRect? {
        didSet { if oldValue != companionCharacterBounds { invalidateOverlay() } }
    }
    var sceneCharacterBounds: NSRect? {
        didSet { if oldValue != sceneCharacterBounds { invalidateOverlay() } }
    }
    var friendMessageBubbles: [PetMessageBubble] = [] {
        didSet { if oldValue != friendMessageBubbles { invalidateOverlay() } }
    }

    func refreshFriendMessagePresentation() { invalidateOverlay() }
    var character: CharacterPack? {
        didSet {
            guard oldValue != character else { return }
            if contentMode.drawsArtwork {
                characterViewBox = character.flatMap(SVGAppearanceRenderer.viewBox)
                rebuildCharacterImage()
            }
            invalidateOverlay()
        }
    }

    var characterScale: Double = 1 {
        didSet {
            guard oldValue != characterScale else { return }
            rebuildArtworkLayer(); updateArtworkTransform(); invalidateOverlay()
        }
    }
    var accessoryPacks: [AccessoryPack] = [] {
        didSet {
            guard oldValue != accessoryPacks else { return }
            if contentMode.drawsArtwork {
                rebuildAccessoryImages(); rebuildCharacterImage()
            }
            rebuildMessageIndicatorImage()
        }
    }
    var accessorySpec = CharacterAccessories(nil) {
        didSet {
            guard oldValue != accessorySpec else { return }
            rebuildAccessoryImages(); rebuildCharacterImage()
        }
    }
    var customization: JSONValue? {
        didSet {
            guard oldValue != customization else { return }
            rebuildCharacterImage()
        }
    }
    var alarmClockVisible = false {
        didSet {
            guard oldValue != alarmClockVisible else { return }
            startAlarmClockTransition(appearing: alarmClockVisible)
        }
    }
    var alarmClockAccessoryID = ClockAccessoryStyle.defaultID {
        didSet {
            let normalized = ClockAccessoryStyle.normalized(alarmClockAccessoryID)
            if normalized != alarmClockAccessoryID { alarmClockAccessoryID = normalized; return }
            guard oldValue != alarmClockAccessoryID else { return }
            rebuildAccessoryImages()
        }
    }
    var alarmRinging = false {
        didSet {
            guard oldValue != alarmRinging else { return }
            syncClockAnimation()
        }
    }
    var clockAlert: ClockState.Alert? {
        didSet {
            guard oldValue != clockAlert else { return }
            invalidateOverlay()
        }
    }
    var locale = "zh-CN" {
        didSet {
            guard oldValue != locale else { return }
            invalidateOverlay()
        }
    }
    var timerText: String? {
        didSet {
            guard oldValue != timerText else { return }
            rebuildArtworkLayer()
            updateArtworkTransform()
            invalidateOverlay()
        }
    }
    var performanceSample: PerformanceSample? {
        didSet {
            guard oldValue != performanceSample else { return }
            if performanceSample != nil {
                performanceFromSample = oldValue ?? .zero
                performanceAnimationElapsed = 0
                performanceAnimationStartedAt = ProcessInfo.processInfo.systemUptime
            } else {
                performanceFromSample = nil
                performanceAnimationElapsed = PerformancePanelAnimation.duration
                performanceAnimationStartedAt = nil
            }
            invalidateOverlay()
            syncAnimationDisplayLink()
        }
    }
    var performancePanelSide = "left" {
        didSet { if oldValue != performancePanelSide { invalidateOverlay() } }
    }
    var performancePanelVerticalPosition = 0.5 {
        didSet { if oldValue != performancePanelVerticalPosition { invalidateOverlay() } }
    }
    var performancePanelDistance = 6.0 {
        didSet { if oldValue != performancePanelDistance { invalidateOverlay() } }
    }
    private(set) var visualBobOffset: CGFloat = 0
    var motionState = PetMotionTiming.State.idle {
        didSet {
            guard oldValue != motionState else { return }
            updateArtworkTransform()
        }
    }
    private(set) var motionElapsed: TimeInterval = 0
    var characterID: String { character?.id ?? "blobfish" }
    func containsInteractivePoint(_ point: NSPoint) -> Bool {
        PetOverlayHitTesting.contains(point, in: interactiveRects)
    }
    private var interactiveRects: [NSRect] {
        var rects: [NSRect] = []
        if contentMode.drawsArtwork {
            rects.append(visibleCharacterBounds.insetBy(dx: -8, dy: -8))
        }
        let needsOverlayLayout = PetOverlayHitTesting.needsSceneLayout(
            hasClockAlert: clockAlert != nil,
            unreadCount: unreadMessageCount,
            hasClickableMessengerSpeech: transientMessage != nil
                && transientMessageEvent == "messenger.received",
            friendBubbleCount: friendMessageBubbles.count
        )
        if contentMode.drawsOverlay, needsOverlayLayout {
            let layout = currentSceneLayout()
            if clockAlert != nil {
                rects += [clockSnoozeRect(in: layout), clockDismissRect(in: layout)]
            }
            if unreadMessageCount > 0 { rects.append(unreadBadgeRect) }
            if transientMessageEvent == "messenger.received", let speech = layout.ownerSpeechRect {
                rects.append(speech)
            }
            rects += layout.ownerFriendBubbleRects + layout.visitorFriendBubbleRects
        }
        if let companionCharacterBounds {
            rects.append(companionCharacterBounds.insetBy(dx: -8, dy: -8))
        }
        return rects
    }

    override func rightMouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onRightDoubleClick?()
            return
        }
        super.rightMouseDown(with: event)
    }

    var characterBounds: NSRect {
        if let sceneCharacterBounds { return sceneCharacterBounds }
        let size = character?.manifest.size ?? CharacterPack.Size(width: 105, height: 90)
        let scaled = NSSize(width: size.width * characterScale, height: size.height * characterScale)
        return NSRect(
            x: bounds.midX - scaled.width / 2,
            y: PetShadowStyle.bottomInset,
            width: scaled.width,
            height: scaled.height
        )
    }
    var visibleCharacterBounds: NSRect {
        characterBounds.offsetBy(dx: 0, dy: visualBobOffset)
    }
    var movementBounds: NSRect {
        let art = characterBounds
        return NSRect(x: art.minX, y: art.minY, width: art.width, height: art.height + Self.bobDistance)
    }
    var snapshot: TaskSnapshot = .idle {
        didSet {
            guard oldValue != snapshot else { return }
            syncCarousel(previous: oldValue)
            syncSpinner()
            invalidateOverlay()
        }
    }

    var direction: CGFloat = 1 {
        didSet {
            if oldValue != direction { updateArtworkTransform() }
        }
    }

    private var blinking = false
    private static let bobDistance: CGFloat = 5
    private var blinkTimer: Timer?
    private var animationDisplayLink: DisplayLinkDriver?
    private var spinnerStartedAt: TimeInterval?
    private var spinnerPhase: CGFloat = 90
    private var carouselIndex = 0
    private var carouselTimer: Timer?
    private var carouselStartedAt: TimeInterval?
    private var carouselFromIndex: Int?
    private var carouselProgress: CGFloat = 1
    private var characterImage: NSImage?
    private var characterViewBox: CGRect?
    private var accessoryImages: [(AccessoryPack, NSImage)] = []
    private var messageIndicatorImage: NSImage?
    private let artworkLayer = CALayer()
    private let overlayLayer = CALayer()
    private var artworkBackingScale: CGFloat = 0
    private var artworkCanvasSize = NSSize.zero
    private var effect: PetVisualEffect?
    private var effectPhase: CGFloat = 0
    private var effectTimer: Timer?
    private var completionTimer: Timer?
    private var completionPhase: CGFloat?
    private var completionAll = false
    private var performanceFromSample: PerformanceSample?
    private var performanceAnimationStartedAt: TimeInterval?
    private var performanceAnimationElapsed = PerformancePanelAnimation.duration
    private var clockAnimationTimer: Timer?
    private var clockShakePhase: CGFloat = 0
    private var alarmClockTransitionTimer: Timer?
    private var alarmClockTransitionPhase: CGFloat?
    private var alarmClockAppearing = true
    private var alarmClockRenderVisible = false
    private var blushLevel = 0
    private var blushTimer: Timer?
    private var moodFaceID: String?
    private(set) var speakingPresentation: PetSpeakingPresentation?
    private var mouseDownScreenPoint: NSPoint?
    private var lastDragScreenPoint: NSPoint?
    private var dragDistance: CGFloat = 0
    private var dragStarted = false
    private var dragSamples: [(time: TimeInterval, dx: CGFloat, dy: CGFloat)] = []
    private enum ClockAction { case snooze(String); case dismiss(String) }
    private var pendingClockAction: ClockAction?
    private var pendingSpeechBubbleClick = false
    private var pendingUnreadBadgeClick = false
    private var pendingCompanionClick = false
    private var pendingSingleClickTimer: Timer?

    init(frame frameRect: NSRect, contentMode: PetViewContentMode = .combined) {
        self.contentMode = contentMode
        super.init(frame: frameRect)
        configureLayers()
    }

    func updateMotion(elapsed: TimeInterval, bobOffset: CGFloat) {
        guard motionElapsed != elapsed || visualBobOffset != bobOffset else { return }
        motionElapsed = elapsed
        visualBobOffset = bobOffset
        updateArtworkTransform()
    }

    required init?(coder: NSCoder) {
        contentMode = .combined
        super.init(coder: coder)
        configureLayers()
    }

    private func configureLayers() {
        wantsLayer = true
        guard let rootLayer = layer else { return }
        rootLayer.backgroundColor = NSColor.clear.cgColor
        rootLayer.masksToBounds = false

        if contentMode.drawsArtwork {
            artworkLayer.contentsGravity = .resize
            artworkLayer.magnificationFilter = .linear
            artworkLayer.minificationFilter = .trilinear
            artworkLayer.masksToBounds = false
            rootLayer.addSublayer(artworkLayer)
        }
        if contentMode.drawsOverlay {
            overlayLayer.delegate = self
            overlayLayer.masksToBounds = false
            rootLayer.addSublayer(overlayLayer)
        }
        updateLayerGeometry()
        if contentMode.drawsArtwork { scheduleBlink() }
    }

    private func invalidateOverlay() {
        overlayLayer.setNeedsDisplay()
    }

    private func updateLayerGeometry() {
        guard !bounds.isEmpty else { return }
        let backingScale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if contentMode.drawsArtwork { artworkLayer.bounds = bounds }
        if contentMode.drawsOverlay {
            overlayLayer.frame = bounds
            overlayLayer.contentsScale = backingScale
        }
        CATransaction.commit()

        let sizeChanged = artworkCanvasSize != bounds.size
        let scaleChanged = abs(artworkBackingScale - backingScale) > 0.001
        if sizeChanged || scaleChanged {
            artworkCanvasSize = bounds.size
            artworkBackingScale = backingScale
            if contentMode.drawsArtwork { rebuildArtworkLayer() }
            if contentMode.drawsOverlay { invalidateOverlay() }
        }
        if contentMode.drawsArtwork { updateArtworkTransform() }
    }

    private func rebuildArtworkLayer() {
        guard artworkLayer.superlayer != nil,
              bounds.width > 0, bounds.height > 0 else { return }
        let scale = max(1, artworkBackingScale > 0 ? artworkBackingScale : 2)
        let pixelWidth = Int(ceil(bounds.width * scale))
        let pixelHeight = Int(ceil(bounds.height * scale))
        guard pixelWidth > 0, pixelHeight > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return }
        context.scaleBy(x: scale, y: scale)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        drawArtworkBase()
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artworkLayer.contentsScale = scale
        artworkLayer.contents = image
        CATransaction.commit()
    }

    private func updateArtworkTransform() {
        guard artworkLayer.superlayer != nil, !bounds.isEmpty else { return }
        let art = characterBounds
        let geometry = effect.map {
            PetEffectGeometry.transform(for: $0, progress: effectPhase, characterID: characterID)
        } ?? PetEffectTransform(scaleX: 1, scaleY: 1, offsetX: 0, offsetY: 0)
        let motion = ambientMotionTransform()
        let speaking = speakingMotionTransform()
        let anchor = CGPoint(
            x: min(1, max(0, art.midX / bounds.width)),
            y: min(1, max(0, art.midY / bounds.height))
        )
        var transform = CATransform3DIdentity
        transform = CATransform3DRotate(transform, motion.rotation * .pi / 180, 0, 0, 1)
        transform = CATransform3DScale(
            transform,
            geometry.scaleX * motion.scaleX * speaking.scaleX * (direction < 0 ? -1 : 1),
            geometry.scaleY * motion.scaleY * speaking.scaleY,
            1
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artworkLayer.anchorPoint = anchor
        artworkLayer.position = CGPoint(
            x: art.midX + geometry.offsetX,
            y: art.midY + geometry.offsetY + visualBobOffset
        )
        artworkLayer.transform = transform
        CATransaction.commit()
    }

    deinit {
        blinkTimer?.invalidate()
        animationDisplayLink?.stop()
        carouselTimer?.invalidate()
        effectTimer?.invalidate()
        completionTimer?.invalidate()
        clockAnimationTimer?.invalidate()
        alarmClockTransitionTimer?.invalidate()
        blushTimer?.invalidate()
        pendingSingleClickTimer?.invalidate()
        if contentMode.drawsOverlay { overlayLayer.delegate = nil }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    override func layout() {
        super.layout()
        updateLayerGeometry()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerGeometry()
    }

    func draw(_ layer: CALayer, in context: CGContext) {
        guard layer === overlayLayer else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        drawOverlay()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawOverlay() {
        let layout = currentSceneLayout()
        drawCompletionEffect()
        drawTimerDisplay(in: layout)
        drawPerformancePanel(in: layout)
        drawSpeechBubble(in: layout)
        drawTaskBubble(in: layout)
        drawClockAlert(in: layout)
        drawVisitStatus(in: layout)
        drawFriendMessageBubbles(in: layout)
        drawUnreadBadge()
    }

    private func currentSceneLayout() -> PetSceneLayout {
        let active = PetMessageBubbleStack.active(friendMessageBubbles, now: Date())
        let ownerSizes = active
            .filter { $0.speaker == .owner }
            .map { friendBubbleMetrics(text: $0.text).size }
        let visitorSizes = active
            .filter { $0.speaker == .visitor }
            .map { friendBubbleMetrics(text: $0.text).size }
        return PetSceneLayoutCoordinator.layout(PetSceneLayoutInput(
            canvas: bounds,
            characterBounds: characterBounds,
            companionBounds: companionCharacterBounds,
            timerSize: timerText == nil ? nil : CGSize(width: 80, height: 25),
            visitStatusSize: visitAnnouncementFriendName.map { visitAnnouncementSize(friendName: $0) },
            clockAlertSize: clockAlert == nil ? nil : CGSize(width: 276, height: 70),
            taskStackSize: snapshot.state == .idle || snapshot.tasks.isEmpty
                ? nil
                : CGSize(width: 294, height: 61),
            ownerSpeechSize: speechBubbleMetrics()?.size,
            ownerFriendBubbleSizes: ownerSizes,
            visitorFriendBubbleSizes: visitorSizes,
            performancePanelSize: performanceSample == nil
                ? nil
                : PerformancePanelGeometry.size(for: characterBounds),
            performancePanelSide: performancePanelSide,
            performancePanelVerticalPosition: performancePanelVerticalPosition,
            performancePanelDistance: performancePanelDistance
        ))
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let layout = currentSceneLayout()
        if companionCharacterBounds?.contains(local) == true {
            pendingCompanionClick = true
            return
        }
        if unreadMessageCount > 0, unreadBadgeRect.contains(local) {
            pendingUnreadBadgeClick = true
            return
        }
        if transientMessageEvent == "messenger.received",
           layout.ownerSpeechRect?.contains(local) == true {
            pendingSpeechBubbleClick = true
            return
        }
        let friendRects = layout.ownerFriendBubbleRects + layout.visitorFriendBubbleRects
        if PetOverlayHitTesting.contains(local, in: friendRects) {
            pendingSpeechBubbleClick = true
            return
        }
        if let alert = clockAlert {
            if clockSnoozeRect(in: layout).contains(local) { pendingClockAction = .snooze(alert.id); return }
            if clockDismissRect(in: layout).contains(local) { pendingClockAction = .dismiss(alert.id); return }
        }
        if event.clickCount == 2 { cancelPendingSingleClick() }
        let point = NSEvent.mouseLocation
        mouseDownScreenPoint = point
        lastDragScreenPoint = point
        dragDistance = 0
        dragStarted = false
        dragSamples.removeAll(keepingCapacity: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !pendingCompanionClick else { return }
        guard !pendingUnreadBadgeClick else { return }
        guard !pendingSpeechBubbleClick else { return }
        guard pendingClockAction == nil else { return }
        guard mouseDownScreenPoint != nil, let previous = lastDragScreenPoint else { return }
        let point = NSEvent.mouseLocation
        let dx = point.x - previous.x
        let dy = point.y - previous.y
        lastDragScreenPoint = point
        dragDistance += hypot(dx, dy)
        guard dragStarted || dragDistance >= PetPrimaryClickIntentPolicy.dragThreshold else { return }
        if !dragStarted {
            dragStarted = true
            cancelPendingSingleClick()
            onDragStart?()
        }
        if dx != 0 || dy != 0 {
            onDragMove?(dx, dy)
            let now = ProcessInfo.processInfo.systemUptime
            dragSamples.append((now, dx, dy))
            dragSamples.removeAll { now - $0.time > 0.30 }
        }
    }

    override func mouseUp(with event: NSEvent) {
        if pendingCompanionClick {
            pendingCompanionClick = false
            let local = convert(event.locationInWindow, from: nil)
            if companionCharacterBounds?.contains(local) == true { onCompanionClick?() }
            return
        }
        if pendingUnreadBadgeClick {
            pendingUnreadBadgeClick = false
            let local = convert(event.locationInWindow, from: nil)
            if unreadMessageCount > 0, unreadBadgeRect.contains(local) {
                onUnreadBadgeClick?()
            }
            return
        }
        if pendingSpeechBubbleClick {
            pendingSpeechBubbleClick = false
            let local = convert(event.locationInWindow, from: nil)
            let layout = currentSceneLayout()
            if transientMessageEvent == "messenger.received",
               layout.ownerSpeechRect?.contains(local) == true {
                onSpeechBubbleClick?(nil)
            } else if let bubble = friendMessageBubble(at: local, in: layout, now: Date()) {
                onSpeechBubbleClick?(bubble.contactID)
            }
            return
        }
        if let pendingClockAction {
            self.pendingClockAction = nil
            switch pendingClockAction {
            case .snooze(let id): onClockSnooze?(id)
            case .dismiss(let id): onClockDismiss?(id)
            }
            return
        }
        defer {
            mouseDownScreenPoint = nil
            lastDragScreenPoint = nil
            dragSamples.removeAll(keepingCapacity: true)
        }
        guard dragStarted else {
            let intent = PetPrimaryClickIntentPolicy.resolve(
                dragDistance: dragDistance,
                clickCount: event.clickCount
            )
            if PetPrimaryClickIntentPolicy.cancelsPendingSingle(intent) {
                cancelPendingSingleClick()
                if intent == .doubleClick { onDoubleClick?() }
            } else {
                if onDoubleClick == nil { onClick?() }
                else { scheduleSingleClick() }
            }
            return
        }
        cancelPendingSingleClick()
        let now = ProcessInfo.processInfo.systemUptime
        guard let last = dragSamples.last, now - last.time < 0.06, dragSamples.count >= 2 else {
            onDragEnd?(0, 0)
            return
        }
        let first = dragSamples[0]
        let duration = max(0.016, last.time - first.time)
        let dx = dragSamples.reduce(CGFloat.zero) { $0 + $1.dx }
        let dy = dragSamples.reduce(CGFloat.zero) { $0 + $1.dy }
        onDragEnd?(dx / duration, dy / duration)
    }

    private func scheduleSingleClick() {
        cancelPendingSingleClick()
        let timer = Timer.scheduledTimer(withTimeInterval: NSEvent.doubleClickInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.pendingSingleClickTimer = nil
            self.onClick?()
        }
        pendingSingleClickTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelPendingSingleClick() {
        pendingSingleClickTimer?.invalidate()
        pendingSingleClickTimer = nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        ignoresMouseInteraction ? nil : super.hitTest(point)
    }

    func showBlush(streak: Int) {
        blushTimer?.invalidate()
        blushLevel = streak >= 3 ? 2 : 1
        rebuildArtworkLayer()
        blushTimer = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: false) { [weak self] _ in
            self?.blushLevel = 0
            self?.blushTimer = nil
            self?.rebuildArtworkLayer()
        }
        RunLoop.main.add(blushTimer!, forMode: .common)
    }

    func setMoodFace(_ id: String?) {
        guard moodFaceID != id else { return }
        moodFaceID = id
        rebuildAccessoryImages()
        rebuildCharacterImage()
    }

    func beginSpeakingPresentation(_ presentation: PetSpeakingPresentation) {
        guard speakingPresentation != presentation else { return }
        speakingPresentation = presentation
        updateArtworkTransform()
    }

    @discardableResult
    func endSpeakingPresentation(token: UUID, now: Date = Date()) -> Bool {
        guard PetSpeakingPresentationPolicy.shouldEnd(
            speakingPresentation,
            token: token,
            now: now
        ) else { return false }
        speakingPresentation = nil
        updateArtworkTransform()
        return true
    }

    func clearSpeakingPresentation() {
        guard speakingPresentation != nil else { return }
        speakingPresentation = nil
        updateArtworkTransform()
    }

    func isSpeakingPresentationActive(at now: Date = Date()) -> Bool {
        PetSpeakingPresentationPolicy.isActive(speakingPresentation, now: now)
    }

    private func drawArtworkBase() {
        guard let characterImage else {
            drawBlobfish()
            return
        }
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        context?.setShouldAntialias(true)
        NSGraphicsContext.current?.imageInterpolation = .high
        context?.setShadow(
            offset: CGSize(width: 0, height: PetShadowStyle.offsetY),
            blur: PetShadowStyle.blurRadius,
            color: CGColor(
                srgbRed: 0,
                green: 0,
                blue: 0,
                alpha: PetShadowStyle.opacity
            )
        )
        context?.beginTransparencyLayer(auxiliaryInfo: nil)
        characterImage.draw(in: characterBounds, from: .zero, operation: .sourceOver, fraction: 1)
        drawAccessories()
        context?.endTransparencyLayer()
        context?.restoreGState()
        drawBlush()
    }

    private func drawBlush() {
        guard let style = PetBlushGeometry.style(
            level: blushLevel,
            characterID: character?.id,
            in: characterBounds
        ), let context = NSGraphicsContext.current?.cgContext else { return }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let centerColor = CGColor(
            colorSpace: colorSpace,
            components: [style.red, style.green, style.blue, style.centerAlpha]
        ), let edgeColor = CGColor(
            colorSpace: colorSpace,
            components: [style.red, style.green, style.blue, 0]
        ), let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [centerColor, edgeColor] as CFArray,
            locations: [0, 1]
        ) else { return }

        for rect in style.cheekRects where rect.width > 0 && rect.height > 0 {
            context.saveGState()
            context.addEllipse(in: rect)
            context.clip()
            context.translateBy(x: rect.midX, y: rect.midY)
            context.scaleBy(x: rect.width / rect.height, y: 1)
            context.drawRadialGradient(
                gradient,
                startCenter: .zero,
                startRadius: 0,
                endCenter: .zero,
                endRadius: rect.height / 2,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
            context.restoreGState()
        }
    }

    private func ambientMotionTransform() -> (rotation: CGFloat, scaleX: CGFloat, scaleY: CGFloat) {
        guard effect == nil else { return (0, 1, 1) }
        if characterID == "grass-buddy" {
            let period: TimeInterval
            let degrees: CGFloat
            let stretch: CGFloat
            switch motionState {
            case .idle: period = 3.6; degrees = 0; stretch = 0.006
            case .roam: period = 0.84; degrees = 0.8; stretch = 0
            case .working: period = 1.25; degrees = 1.2; stretch = 0.009
            case .waiting: period = 2.8; degrees = 1.5; stretch = 0
            }
            let wave = CGFloat(sin(motionElapsed / period * 2 * .pi))
            let amount = stretch * (wave + 1)
            return (degrees * wave, 1 + amount, 1 - amount)
        }
        if motionState == .waiting {
            let rotation = -CGFloat(1 - cos(motionElapsed / 2.2 * 2 * .pi))
            return (rotation, 1, 1)
        }
        if motionState == .working {
            let amount = CGFloat((1 - cos(motionElapsed / 1.5 * 2 * .pi)) * 0.0125)
            return (0, 1 + amount, 1)
        }
        return (0, 1, 1)
    }

    private func speakingMotionTransform() -> (scaleX: CGFloat, scaleY: CGFloat) {
        guard isSpeakingPresentationActive() else { return (1, 1) }
        let wave = CGFloat((sin(motionElapsed / 0.32 * 2 * .pi) + 1) / 2)
        return (1 + 0.012 * wave, 1 - 0.008 * wave)
    }

    private func rebuildAccessoryImages() {
        let byID = Dictionary(uniqueKeysWithValues: accessoryPacks.map { ($0.id, $0) })
        var equipped = accessorySpec.equipped
        if let moodFaceID { equipped["face"] = moodFaceID }
        let ids = AccessoryLayerOrder.orderedIDs(
            equipped: equipped,
            systemAccessoryIDs: alarmClockRenderVisible ? [alarmClockAccessoryID] : []
        )
        accessoryImages = ids.compactMap { id in
            guard let pack = byID[id], let image = NSImage(contentsOf: pack.artURL) else { return nil }
            return (pack, image)
        }
        rebuildArtworkLayer()
    }

    private func rebuildCharacterImage() {
        let faceID = moodFaceID ?? accessorySpec.equipped["face"]
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
        rebuildArtworkLayer()
    }

    private func drawAccessories() {
        guard let character, let sourceSize = characterImage?.size,
              sourceSize.width > 0, sourceSize.height > 0 else { return }
        let target = characterBounds
        let canvas = characterViewBox ?? CGRect(origin: .zero, size: sourceSize)
        guard canvas.width > 0, canvas.height > 0 else { return }
        let scaleX = target.width / canvas.width
        let scaleY = target.height / canvas.height
        for (pack, image) in accessoryImages {
            guard let slot = character.manifest.accessories?.slots[pack.manifest.slot] else { continue }
            let tuning = accessorySpec.tuning[pack.id] ?? AccessoryTuning(nil)
            let unitX = scaleX * slot.scale * tuning.size * tuning.width
            let unitY = scaleY * slot.scale * tuning.size * tuning.height
            // Every slot anchor is authored inside the character's own SVG
            // coordinate space. A non-zero viewBox origin (the wotou fish
            // starts at x = -16) must therefore be removed before projecting
            // any slot anchor into the AppKit target rectangle - not just the
            // face's, or accessories on that origin end up shifted relative
            // to the body. Tunable props keep their existing offset contract
            // and remain independent.
            let imageSize = image.size
            let isClock = pack.manifest.slot == "clock"
            let shake = alarmRinging && isClock ? sin(clockShakePhase) * 3 : 0
            let renderedSize = NSSize(width: imageSize.width * unitX, height: imageSize.height * unitY)
            var rect: NSRect
            if isClock {
                rect = ClockAccessoryPositionGeometry.centeredRect(
                    offsetX: tuning.offsetX,
                    offsetY: tuning.offsetY,
                    canvas: canvas,
                    characterBounds: target,
                    containerBounds: bounds,
                    renderedSize: renderedSize
                )
                rect.origin.x += shake
            } else {
                let targetAnchor = ExpressionCanvasGeometry.targetAnchor(
                    slotX: slot.x + tuning.offsetX,
                    slotY: slot.y + tuning.offsetY,
                    canvas: canvas,
                    target: target
                )
                rect = NSRect(
                    x: targetAnchor.x - pack.manifest.anchor.x * unitX,
                    y: targetAnchor.y - (imageSize.height - pack.manifest.anchor.y) * unitY,
                    width: renderedSize.width,
                    height: renderedSize.height
                )
            }
            var alpha: CGFloat = 1
            var rotation: CGFloat = 0
            if isClock, let phase = alarmClockTransitionPhase {
                let geometry = alarmClockTransitionGeometry(progress: phase, appearing: alarmClockAppearing)
                rect = NSRect(
                    x: rect.midX - rect.width * geometry.scale / 2,
                    y: rect.midY - rect.height * geometry.scale / 2 + geometry.offsetY,
                    width: rect.width * geometry.scale,
                    height: rect.height * geometry.scale
                )
                alpha = geometry.opacity
                rotation = geometry.rotation
            }
            NSGraphicsContext.saveGraphicsState()
            if rotation != 0 {
                let transform = NSAffineTransform()
                transform.translateX(by: rect.midX, yBy: rect.midY)
                transform.rotate(byDegrees: rotation)
                transform.translateX(by: -rect.midX, yBy: -rect.midY)
                transform.concat()
            }
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func rebuildMessageIndicatorImage() {
        guard contentMode.drawsOverlay,
              let pack = accessoryPacks.first(where: {
                  $0.id == messageIndicatorID && $0.manifest.slot == "message-indicator"
              }) else {
            messageIndicatorImage = nil
            return
        }
        messageIndicatorImage = NSImage(contentsOf: pack.artURL)
    }

    private func startAlarmClockTransition(appearing: Bool) {
        alarmClockTransitionTimer?.invalidate()
        alarmClockAppearing = appearing
        alarmClockTransitionPhase = 0
        if appearing {
            alarmClockRenderVisible = true
            rebuildAccessoryImages()
        }
        let duration: TimeInterval = appearing ? 0.52 : 0.44
        let started = Date()
        alarmClockTransitionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / PetMotionTiming.framesPerSecond, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.alarmClockTransitionPhase = min(1, CGFloat(Date().timeIntervalSince(started) / duration))
            if self.alarmClockTransitionPhase == 1 {
                timer.invalidate()
                self.alarmClockTransitionTimer = nil
                self.alarmClockTransitionPhase = nil
                if !appearing {
                    self.alarmClockRenderVisible = false
                    self.rebuildAccessoryImages()
                }
            }
            self.rebuildArtworkLayer()
        }
        RunLoop.main.add(alarmClockTransitionTimer!, forMode: .common)
    }

    private func alarmClockTransitionGeometry(
        progress: CGFloat,
        appearing: Bool
    ) -> (scale: CGFloat, opacity: CGFloat, offsetY: CGFloat, rotation: CGFloat) {
        let value = min(1, max(0, progress))
        if !appearing {
            return (1 - 0.38 * value, 1 - value, -9 * value, 8 * value)
        }
        if value <= 0.62 {
            let local = value / 0.62
            return (0.55 + 0.53 * local, local, -10 + 12 * local, -9 + 12 * local)
        }
        let local = (value - 0.62) / 0.38
        return (1.08 - 0.08 * local, 1, 2 - 2 * local, 3 - 3 * local)
    }

    private func drawTimerDisplay(in layout: PetSceneLayout) {
        guard let timerText, let rect = layout.timerRect else { return }
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

    private func drawPerformancePanel(in layout: PetSceneLayout) {
        guard let target = performanceSample, let rect = layout.performancePanelRect else { return }
        let source = performanceFromSample ?? target
        let elapsed = performanceAnimationElapsed
        let cpuTotal = PerformancePanelAnimation.interpolate(
            source.systemCPUPercent,
            target.systemCPUPercent,
            progress: PerformancePanelAnimation.progress(elapsed: elapsed, delay: 0)
        )
        let cpuApp = PerformancePanelAnimation.interpolate(
            source.appCPUPercent,
            target.appCPUPercent,
            progress: PerformancePanelAnimation.progress(elapsed: elapsed, delay: 0.08)
        )
        let ramTotal = PerformancePanelAnimation.interpolate(
            source.systemRAMPercent,
            target.systemRAMPercent,
            progress: PerformancePanelAnimation.progress(elapsed: elapsed, delay: 0.08)
        )
        let ramApp = PerformancePanelAnimation.interpolate(
            source.appRAMPercent,
            target.appRAMPercent,
            progress: PerformancePanelAnimation.progress(elapsed: elapsed, delay: 0.16)
        )
        let visualScale = min(1.5, max(0.65, rect.height / 90))
        let grassTheme = characterID == "grass-buddy"
        let background = grassTheme
            ? NSColor(srgbRed: 0.977, green: 0.982, blue: 0.934, alpha: 0.94)
            : NSColor(srgbRed: 1, green: 0.969, blue: 0.976, alpha: 0.94)
        let outline = grassTheme
            ? NSColor(srgbRed: 0.49, green: 0.55, blue: 0.31, alpha: 0.28)
            : NSColor(srgbRed: 0.78, green: 0.49, blue: 0.58, alpha: 0.25)
        let track = grassTheme
            ? NSColor(srgbRed: 0.933, green: 0.941, blue: 0.847, alpha: 0.9)
            : NSColor(srgbRed: 0.973, green: 0.910, blue: 0.929, alpha: 0.9)
        let systemColor = grassTheme
            ? NSColor(srgbRed: 0.804, green: 0.831, blue: 0.565, alpha: 0.92)
            : NSColor(srgbRed: 0.945, green: 0.804, blue: 0.839, alpha: 0.94)
        let appColor = grassTheme
            ? NSColor(srgbRed: 0.39, green: 0.48, blue: 0.23, alpha: 0.98)
            : NSColor(srgbRed: 0.78, green: 0.49, blue: 0.58, alpha: 0.98)
        let textColor = NSColor(srgbRed: 0.29, green: 0.36, blue: 0.35, alpha: 1)
        let cornerRadius = 8 * visualScale
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 5 * visualScale
        shadow.shadowOffset = NSSize(width: 0, height: -1.5 * visualScale)
        shadow.shadowColor = NSColor(calibratedRed: 0.15, green: 0.21, blue: 0.20, alpha: 0.10)
        shadow.set()
        background.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        outline.setStroke()
        path.lineWidth = 1
        path.stroke()

        let columns = [
            ("CPU", cpuTotal, cpuApp, 0.0),
            ("RAM", ramTotal, ramApp, 0.08),
        ]
        for (index, column) in columns.enumerated() {
            let centerX = rect.minX + rect.width * (index == 0 ? 0.28 : 0.72)
            drawPerformanceColumn(
                label: column.0,
                total: column.1,
                app: column.2,
                centerX: centerX,
                panelRect: rect,
                trackColor: track,
                systemColor: systemColor,
                appColor: appColor,
                textColor: textColor,
                grassTheme: grassTheme,
                visualScale: visualScale,
                decorationDelay: column.3
            )
        }
        let memory = String(format: "%.0f MB", target.appMemoryMB) as NSString
        drawCentered(
            memory,
            at: NSPoint(x: rect.midX, y: rect.minY + 4 * visualScale),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: max(5.5, 7 * visualScale),
                    weight: .medium
                ),
                .foregroundColor: textColor.withAlphaComponent(0.76),
            ]
        )
    }

    private func drawPerformanceColumn(
        label: String,
        total: Double,
        app: Double,
        centerX: CGFloat,
        panelRect: CGRect,
        trackColor: NSColor,
        systemColor: NSColor,
        appColor: NSColor,
        textColor: NSColor,
        grassTheme: Bool,
        visualScale: CGFloat,
        decorationDelay: TimeInterval
    ) {
        let nested = PerformancePanelAnimation.nested(total: total, app: app)
        drawCentered(
            label as NSString,
            at: NSPoint(x: centerX, y: panelRect.maxY - 11 * visualScale),
            attributes: [
                .font: NSFont.systemFont(ofSize: max(6, 8 * visualScale), weight: .semibold),
                .foregroundColor: textColor.withAlphaComponent(0.72),
            ]
        )
        drawCentered(
            String(format: "%.0f%%", nested.total) as NSString,
            at: NSPoint(x: centerX, y: panelRect.maxY - 23 * visualScale),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: max(6.5, 9 * visualScale),
                    weight: .bold
                ),
                .foregroundColor: textColor,
            ]
        )

        let barBottom = panelRect.minY + 18 * visualScale
        let barTop = panelRect.maxY - 29 * visualScale
        let barWidth = max(5.5, 9 * visualScale)
        let bar = CGRect(
            x: centerX - barWidth / 2,
            y: barBottom,
            width: barWidth,
            height: max(10, barTop - barBottom)
        )
        trackColor.setFill()
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        let totalHeight = bar.height * CGFloat(nested.total / 100)
        if totalHeight > 0 {
            let fill = CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: max(1, totalHeight))
            systemColor.setFill()
            NSBezierPath(
                roundedRect: fill,
                xRadius: min(barWidth / 2, fill.height / 2),
                yRadius: min(barWidth / 2, fill.height / 2)
            ).fill()
        }
        let appHeight = min(totalHeight, bar.height * CGFloat(nested.app / 100))
        if appHeight > 0 {
            let fill = CGRect(
                x: bar.minX,
                y: bar.minY,
                width: bar.width,
                height: max(1.5 * visualScale, appHeight)
            )
            appColor.setFill()
            NSBezierPath(
                roundedRect: fill,
                xRadius: min(barWidth / 2, fill.height / 2),
                yRadius: min(barWidth / 2, fill.height / 2)
            ).fill()
        }
        drawPerformanceDecoration(
            at: NSPoint(x: centerX, y: bar.minY + max(2, totalHeight)),
            color: appColor,
            grassTheme: grassTheme,
            visualScale: visualScale,
            delay: decorationDelay
        )

        let role = locale == "en" ? "Pet" : (grassTheme ? "草" : "鱼")
        drawCentered(
            String(format: "%@ %.0f%%", role, nested.app) as NSString,
            at: NSPoint(x: centerX, y: panelRect.minY + 11 * visualScale),
            attributes: [
                .font: NSFont.systemFont(
                    ofSize: max(5.5, 7 * visualScale),
                    weight: .semibold
                ),
                .foregroundColor: appColor,
            ]
        )
    }

    private func drawPerformanceDecoration(
        at point: NSPoint,
        color: NSColor,
        grassTheme: Bool,
        visualScale: CGFloat,
        delay: TimeInterval
    ) {
        guard performanceAnimationStartedAt != nil else { return }
        let progress = PerformancePanelAnimation.progress(elapsed: performanceAnimationElapsed, delay: delay)
        let fade = 1 - progress
        guard fade > 0.01 else { return }
        color.withAlphaComponent(0.65 * fade).setFill()
        color.withAlphaComponent(0.72 * fade).setStroke()
        if grassTheme {
            let sway = sin(progress * .pi * 2) * 2 * visualScale
            let stem = NSBezierPath()
            stem.move(to: point)
            stem.curve(
                to: NSPoint(x: point.x + sway, y: point.y + 7 * visualScale),
                controlPoint1: NSPoint(x: point.x, y: point.y + 3 * visualScale),
                controlPoint2: NSPoint(x: point.x + sway, y: point.y + 5 * visualScale)
            )
            stem.lineWidth = 1.1 * visualScale
            stem.stroke()
            NSBezierPath(ovalIn: CGRect(
                x: point.x + sway - 5 * visualScale,
                y: point.y + 4 * visualScale,
                width: 5 * visualScale,
                height: 3 * visualScale
            )).fill()
            NSBezierPath(ovalIn: CGRect(
                x: point.x + sway,
                y: point.y + 5 * visualScale,
                width: 5 * visualScale,
                height: 3 * visualScale
            )).fill()
        } else {
            let lift = CGFloat(progress) * 8 * visualScale
            NSBezierPath(ovalIn: CGRect(
                x: point.x + 3 * visualScale,
                y: point.y + 2 * visualScale + lift,
                width: 3.5 * visualScale,
                height: 3.5 * visualScale
            )).fill()
            NSBezierPath(ovalIn: CGRect(
                x: point.x - 5 * visualScale,
                y: point.y + 5 * visualScale + lift * 0.65,
                width: 2.5 * visualScale,
                height: 2.5 * visualScale
            )).fill()
        }
    }

    private func drawCentered(
        _ text: NSString,
        at point: NSPoint,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), withAttributes: attributes)
    }

    private func syncClockAnimation() {
        clockAnimationTimer?.invalidate(); clockAnimationTimer = nil
        guard alarmRinging else {
            clockShakePhase = 0
            rebuildArtworkLayer()
            return
        }
        clockAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / PetMotionTiming.framesPerSecond, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.clockShakePhase += 0.4
            self.rebuildArtworkLayer()
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

        let noseX = body.minX - 6
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

    private func drawTaskBubble(in layout: PetSceneLayout) {
        guard snapshot.state != .idle, let taskStackRect = layout.taskStackRect else { return }
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
                showsPosition: entry.showsPosition,
                taskStackRect: taskStackRect
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

    private func speechBubbleMetrics() -> (size: CGSize, attributes: [NSAttributedString.Key: Any])? {
        guard let transientMessage else { return nil }
        let isMessengerMessage = transientMessageEvent == "messenger.received"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1.5
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: isMessengerMessage
                ? NSColor.white
                : NSColor(calibratedRed: 0.18, green: 0.16, blue: 0.17, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        let measured = (transientMessage as NSString).boundingRect(
            with: NSSize(width: 244, height: 52),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return (
            CGSize(
                width: min(260, max(32, ceil(measured.width) + 16)),
                height: min(60, max(24, ceil(measured.height) + 8))
            ),
            attributes
        )
    }

    private func drawSpeechBubble(in layout: PetSceneLayout) {
        guard let transientMessage,
              let rect = layout.ownerSpeechRect,
              let metrics = speechBubbleMetrics() else {
            return
        }
        let isMessengerMessage = transientMessageEvent == "messenger.received"

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
        shadow.set()
        (isMessengerMessage
            ? NSColor.fishHex(transientMessageColor) ?? NSColor(calibratedRed: 0.12, green: 0.48, blue: 0.92, alpha: 0.98)
            : NSColor.white.withAlphaComponent(0.98)).setFill()
        let bubble = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        bubble.fill()
        NSGraphicsContext.restoreGraphicsState()
        (transientMessage as NSString).draw(
            in: rect.insetBy(dx: 8, dy: 4),
            withAttributes: metrics.attributes
        )
    }

    private func drawUnreadBadge() {
        guard unreadMessageCount > 0 else { return }
        let rect = unreadBadgeRect
        if let messageIndicatorImage {
            messageIndicatorImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            NSColor(calibratedWhite: 0.96, alpha: 0.98).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        }
        let label = unreadMessageCount > 9 ? "9+" : String(unreadMessageCount)
        let font = NSFont.systemFont(ofSize: label.count > 1 ? 7.5 : 9, weight: .heavy)
        let color = messageIndicatorID == "message-envelope" ? NSColor.white : NSColor.fishHex("#355A66")!
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let countRect = unreadCountRect(in: rect)
        let size = (label as NSString).size(withAttributes: attributes)
        (label as NSString).draw(
            at: NSPoint(x: countRect.midX - size.width / 2, y: countRect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private var unreadBadgeRect: NSRect {
        NSRect(x: characterBounds.maxX - 13, y: characterBounds.maxY - 5, width: 42, height: 42)
    }

    private func unreadCountRect(in rect: NSRect) -> NSRect {
        let source: NSRect
        switch messageIndicatorID {
        case "message-envelope": source = NSRect(x: 38, y: 57, width: 24, height: 24)
        case "message-flying-letter": source = NSRect(x: 48, y: 47, width: 26, height: 22)
        case "message-sea-mail": source = NSRect(x: 31, y: 55, width: 39, height: 27)
        default: source = NSRect(x: 70, y: 13, width: 22, height: 17)
        }
        return NSRect(
            x: rect.minX + source.minX / 100 * rect.width,
            y: rect.maxY - source.maxY / 100 * rect.height,
            width: source.width / 100 * rect.width,
            height: source.height / 100 * rect.height
        )
    }

    private func drawFriendMessageBubbles(in layout: PetSceneLayout) {
        let now = Date()
        let active = PetMessageBubbleStack.active(friendMessageBubbles, now: now)
        guard !active.isEmpty else { return }

        for speaker in [PetMessageSpeaker.owner, .visitor] {
            let entries = active.filter { $0.speaker == speaker }
            guard !entries.isEmpty else { continue }
            let anchor = speaker == .visitor ? companionCharacterBounds ?? characterBounds : characterBounds
            let metrics = entries.map { friendBubbleMetrics(text: $0.text) }
            let rects = speaker == .visitor
                ? layout.visitorFriendBubbleRects
                : layout.ownerFriendBubbleRects
            guard rects.count == entries.count else { continue }
            for (localIndex, entry) in entries.enumerated() {
                let distance = entries.count - 1 - localIndex
                drawFriendBubble(
                    entry,
                    rect: rects[localIndex],
                    attributes: metrics[localIndex].attributes,
                    opacity: PetMessageBubbleStack.opacity(
                        distanceFromNewest: distance,
                        expiresAt: entry.expiresAt,
                        now: now
                    ),
                    anchor: anchor
                )
            }
        }
    }

    private func friendMessageBubble(
        at point: NSPoint,
        in layout: PetSceneLayout,
        now: Date
    ) -> PetMessageBubble? {
        let active = PetMessageBubbleStack.active(friendMessageBubbles, now: now)
        let owners = active.filter { $0.speaker == .owner }
        let visitors = active.filter { $0.speaker == .visitor }
        for (bubble, rect) in zip(owners, layout.ownerFriendBubbleRects) where rect.contains(point) {
            return bubble
        }
        for (bubble, rect) in zip(visitors, layout.visitorFriendBubbleRects) where rect.contains(point) {
            return bubble
        }
        return nil
    }

    private func friendBubbleMetrics(
        text: String
    ) -> (size: CGSize, attributes: [NSAttributedString.Key: Any]) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1.2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: 210, height: 48),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return (
            NSSize(width: min(226, max(42, ceil(measured.width) + 18)), height: min(56, max(26, ceil(measured.height) + 10))),
            attributes
        )
    }

    private func drawFriendBubble(
        _ bubble: PetMessageBubble,
        rect: NSRect,
        attributes: [NSAttributedString.Key: Any],
        opacity: CGFloat,
        anchor: NSRect
    ) {
        let color = (NSColor.fishHex(bubble.color)
            ?? NSColor(calibratedRed: 0.12, green: 0.48, blue: 0.92, alpha: 0.98))
            .withAlphaComponent(opacity)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.16 * opacity)
        shadow.set()
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        let tail = NSBezierPath()
        if rect.minY >= anchor.maxY {
            let center = min(max(anchor.midX, rect.minX + 14), rect.maxX - 14)
            tail.move(to: NSPoint(x: center - 6, y: rect.minY + 1))
            tail.line(to: NSPoint(x: center, y: max(anchor.maxY, rect.minY - 6)))
            tail.line(to: NSPoint(x: center + 6, y: rect.minY + 1))
        } else if rect.maxY <= anchor.minY {
            let center = min(max(anchor.midX, rect.minX + 14), rect.maxX - 14)
            tail.move(to: NSPoint(x: center - 6, y: rect.maxY - 1))
            tail.line(to: NSPoint(x: center, y: min(anchor.minY, rect.maxY + 6)))
            tail.line(to: NSPoint(x: center + 6, y: rect.maxY - 1))
        } else if rect.midX < anchor.midX {
            let center = min(max(anchor.midY, rect.minY + 14), rect.maxY - 14)
            tail.move(to: NSPoint(x: rect.maxX - 1, y: center - 6))
            tail.line(to: NSPoint(x: min(anchor.minX, rect.maxX + 6), y: center))
            tail.line(to: NSPoint(x: rect.maxX - 1, y: center + 6))
        } else {
            let center = min(max(anchor.midY, rect.minY + 14), rect.maxY - 14)
            tail.move(to: NSPoint(x: rect.minX + 1, y: center - 6))
            tail.line(to: NSPoint(x: max(anchor.maxX, rect.minX - 6), y: center))
            tail.line(to: NSPoint(x: rect.minX + 1, y: center + 6))
        }
        tail.close()
        tail.fill()
        NSGraphicsContext.restoreGraphicsState()

        var fadedAttributes = attributes
        fadedAttributes[.foregroundColor] = bubble.color?.uppercased() == "#FFFFFF"
            ? NSColor(calibratedWhite: 0.18, alpha: opacity)
            : NSColor.white.withAlphaComponent(opacity)
        (bubble.text as NSString).draw(
            in: rect.insetBy(dx: 9, dy: 5),
            withAttributes: fadedAttributes
        )
    }

    private func drawVisitStatus(in layout: PetSceneLayout) {
        if let friendName = visitAnnouncementFriendName, let rect = layout.visitStatusRect {
            NSColor(calibratedRed: 1, green: 0.91, blue: 0.94, alpha: 0.96).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            (visitAnnouncementText(friendName: friendName) as NSString).draw(
                in: rect.insetBy(dx: 6, dy: 3),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: NSColor(calibratedRed: 0.66, green: 0.22, blue: 0.35, alpha: 1),
                ]
            )
        }
        if let status = visitingFriendStatus, let companionCharacterBounds {
            (status.emoji as NSString).draw(
                at: NSPoint(x: companionCharacterBounds.midX - 9, y: companionCharacterBounds.maxY + 2),
                withAttributes: [.font: NSFont.systemFont(ofSize: 18)]
            )
        }
    }

    private func visitAnnouncementText(friendName: String) -> String {
        locale == "en"
            ? "♡ Visiting hand in hand with \(friendName)"
            : "♡ 與 \(friendName) 牽手串門中"
    }

    private func visitAnnouncementSize(friendName: String) -> CGSize {
        let text = visitAnnouncementText(friendName: friendName) as NSString
        let width = ceil(text.size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
        ]).width)
        return CGSize(width: min(260, max(166, width + 12)), height: 21)
    }

    private func clockSnoozeRect(in layout: PetSceneLayout) -> NSRect {
        guard let rect = layout.clockAlertRect else { return .zero }
        return NSRect(x: rect.minX + 10, y: rect.minY + 9, width: 124, height: 25)
    }

    private func clockDismissRect(in layout: PetSceneLayout) -> NSRect {
        guard let rect = layout.clockAlertRect else { return .zero }
        return NSRect(x: rect.midX + 3, y: rect.minY + 9, width: 128, height: 25)
    }

    private func drawClockAlert(in layout: PetSceneLayout) {
        guard let alert = clockAlert, let rect = layout.clockAlertRect else { return }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.shadowColor = NSColor(calibratedRed: 0.20, green: 0.16, blue: 0.11, alpha: 0.18)
        shadow.set()
        NSColor(calibratedRed: 1, green: 0.976, blue: 0.929, alpha: 0.98).setFill()
        let card = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        card.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedRed: 0.62, green: 0.42, blue: 0.22, alpha: 0.28).setStroke()
        card.lineWidth = 1
        card.stroke()

        let english = locale == "en"
        let kind = (alert.sourceType == "alarm"
            ? (english ? "ALARM" : "闹钟到了")
            : (english ? "TIMER" : "计时结束")) as NSString
        kind.draw(at: NSPoint(x: rect.minX + 10, y: rect.maxY - 20), withAttributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .heavy),
            .foregroundColor: NSColor(calibratedRed: 0.61, green: 0.42, blue: 0.21, alpha: 1),
            .kern: 1.1,
        ])
        let title = (alert.label.isEmpty ? (english ? "Time is up" : "时间到了") : alert.label) as NSString
        title.draw(in: NSRect(x: rect.minX + 10, y: rect.minY + 37, width: rect.width - 20, height: 17), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.35, green: 0.29, blue: 0.21, alpha: 1),
        ])
        drawClockButton(clockSnoozeRect(in: layout), title: english ? "Snooze 5 min" : "再等 5 分钟", primary: false)
        drawClockButton(clockDismissRect(in: layout), title: english ? "Dismiss" : "知道了", primary: true)
    }

    private func drawClockButton(_ rect: NSRect, title: String, primary: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        (primary
            ? NSColor(calibratedRed: 0.48, green: 0.40, blue: 0.31, alpha: 1)
            : NSColor.white).setFill()
        path.fill()
        if !primary {
            NSColor(calibratedRed: 0.49, green: 0.35, blue: 0.20, alpha: 0.20).setStroke()
            path.stroke()
        }
        let value = title as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: primary ? NSColor.white : NSColor(calibratedRed: 0.41, green: 0.34, blue: 0.25, alpha: 1),
        ]
        let size = value.size(withAttributes: attributes)
        value.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }

    private func drawTaskCard(
        _ card: TaskCard,
        placement: TaskCarouselPlacement,
        position: Int,
        total: Int,
        showsPosition: Bool,
        taskStackRect: NSRect
    ) {
        let font = NSFont.systemFont(ofSize: 11, weight: placement.depth == 0 ? .semibold : .medium)
        let countWidth: CGFloat = showsPosition && total > 1 ? 34 : 0
        let measuredTitle = (card.title as NSString).size(withAttributes: [.font: font]).width
        let unscaledWidth = min(270, max(178, measuredTitle + 42 + countWidth))
        let width = unscaledWidth * placement.scale
        let height = 26 * placement.scale
        let frontY = taskStackRect.minY + 31
        let rect = NSRect(
            x: taskStackRect.midX + placement.horizontalOffset - width / 2,
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

    func playCompletionEffect(all: Bool) {
        if contentMode.drawsArtwork { playEffect(.completed) }
        completionTimer?.invalidate()
        completionAll = all
        completionPhase = 0
        let duration: TimeInterval = all ? 2 : 1.4
        let started = Date()
        completionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / PetMotionTiming.framesPerSecond, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.completionPhase = min(1, CGFloat(Date().timeIntervalSince(started) / duration))
            if self.completionPhase == 1 {
                timer.invalidate()
                self.completionTimer = nil
                self.completionPhase = nil
            }
            self.invalidateOverlay()
        }
        RunLoop.main.add(completionTimer!, forMode: .common)
    }

    private func drawCompletionEffect() {
        guard let phase = completionPhase else { return }
        let opacity: CGFloat
        let scale: CGFloat
        let yOffset: CGFloat
        switch phase {
        case ..<0.18:
            let local = phase / 0.18
            opacity = local; scale = 0.55 + 0.45 * local; yOffset = 7 * (1 - local)
        case ..<0.68:
            opacity = 1; scale = 1; yOffset = 0
        case ..<0.82:
            let local = (phase - 0.68) / 0.14
            opacity = 1; scale = 1 - 0.07 * local; yOffset = 0
        default:
            let local = (phase - 0.82) / 0.18
            opacity = 1 - local; scale = 0.93 - 0.18 * local; yOffset = -3 * local
        }
        let center = NSPoint(x: characterBounds.midX + 53, y: characterBounds.maxY - 28 + yOffset)
        let rect = NSRect(x: center.x - 14 * scale, y: center.y - 14 * scale, width: 28 * scale, height: 28 * scale)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.shadowColor = NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.21, alpha: 0.32 * opacity)
        shadow.set()
        (completionAll
            ? NSColor(calibratedRed: 0.31, green: 0.53, blue: 0.45, alpha: opacity)
            : NSColor(calibratedRed: 0.43, green: 0.62, blue: 0.47, alpha: opacity)).setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.94 * opacity).setStroke()
        let ring = NSBezierPath(ovalIn: rect)
        ring.lineWidth = 2
        ring.stroke()
        let check = "✓" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18 * scale, weight: .heavy),
            .foregroundColor: NSColor.white.withAlphaComponent(opacity),
        ]
        let size = check.size(withAttributes: attributes)
        check.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
    }

    func playClickEffect() { startEffect(.hit, duration: 0.5) }

    func playBumpEffect() { startEffect(.bump, duration: 0.32) }

    func playFriendlyEffect() { startEffect(.success, duration: 0.72) }

    private func startEffect(_ visualEffect: PetVisualEffect, duration: TimeInterval) {
        effectTimer?.invalidate()
        effect = visualEffect
        effectPhase = 0
        updateArtworkTransform()
        let started = Date()
        effectTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / PetMotionTiming.framesPerSecond, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.effectPhase = CGFloat(Date().timeIntervalSince(started) / duration)
            if self.effectPhase >= 1 {
                timer.invalidate()
                self.effectTimer = nil
                self.effect = nil
            }
            self.updateArtworkTransform()
        }
        RunLoop.main.add(effectTimer!, forMode: .common)
    }

    private func drawStatusIcon(state: TaskDisplayState, at center: NSPoint, alpha: CGFloat) {
        switch state {
        case .running:
            let base = NSBezierPath(ovalIn: NSRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12))
            NSColor(srgbRed: 0.843, green: 0.882, blue: 0.886, alpha: alpha).setStroke()
            base.lineWidth = 2
            base.stroke()
            NSColor(srgbRed: 0.424, green: 0.573, blue: 0.584, alpha: alpha).setStroke()
            let spinner = NSBezierPath()
            spinner.appendArc(withCenter: center, radius: 6, startAngle: spinnerPhase, endAngle: spinnerPhase + 90)
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
        spinnerStartedAt = TaskSpinnerTimeline.start(
            current: spinnerStartedAt,
            hasRunningTask: snapshot.tasks.contains(where: { $0.state == .running }),
            now: ProcessInfo.processInfo.systemUptime
        )
        if spinnerStartedAt == nil { spinnerPhase = 90 }
        syncAnimationDisplayLink()
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
        carouselStartedAt = nil
        let oldIndex = carouselIndex
        carouselIndex = index
        guard animated else {
            carouselFromIndex = nil
            carouselProgress = 1
            invalidateOverlay()
            return
        }
        carouselFromIndex = oldIndex
        carouselProgress = 0
        carouselStartedAt = ProcessInfo.processInfo.systemUptime
        syncAnimationDisplayLink()
    }

    private func syncAnimationDisplayLink() {
        if spinnerStartedAt != nil || carouselStartedAt != nil || performanceAnimationStartedAt != nil {
            if animationDisplayLink == nil {
                animationDisplayLink = DisplayLinkDriver { [weak self] uptime in
                    self?.advanceDisplayAnimations(uptime: uptime)
                }
            }
            animationDisplayLink?.start()
        } else {
            animationDisplayLink?.stop()
        }
    }

    private func advanceDisplayAnimations(uptime: TimeInterval) {
        var changed = false
        if let spinnerStartedAt {
            spinnerPhase = TaskSpinnerTimeline.angle(start: spinnerStartedAt, now: uptime)
            changed = true
        }
        if let carouselStartedAt {
            let linear = min(1, CGFloat((uptime - carouselStartedAt) / 0.24))
            carouselProgress = TaskCarouselGeometry.transitionProgress(linear)
            changed = true
            if linear >= 1 {
                self.carouselStartedAt = nil
                carouselFromIndex = nil
                carouselProgress = 1
            }
        }
        if let performanceAnimationStartedAt {
            performanceAnimationElapsed = max(0, uptime - performanceAnimationStartedAt)
            changed = true
            if performanceAnimationElapsed >= PerformancePanelAnimation.duration {
                self.performanceAnimationStartedAt = nil
                performanceAnimationElapsed = PerformancePanelAnimation.duration
                performanceFromSample = performanceSample
            }
        }
        if changed { invalidateOverlay() }
        syncAnimationDisplayLink()
    }

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 3.5...8.5), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.blinking = true
            self.rebuildCharacterImage()
            self.blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: false) { [weak self] _ in
                self?.blinking = false
                self?.rebuildCharacterImage()
                self?.scheduleBlink()
            }
        }
    }
}

private extension NSColor {
    static func fishHex(_ value: String?) -> NSColor? {
        guard let value else { return nil }
        let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let number = Int(hex, radix: 16) else { return nil }
        return NSColor(
            calibratedRed: CGFloat((number >> 16) & 0xff) / 255,
            green: CGFloat((number >> 8) & 0xff) / 255,
            blue: CGFloat(number & 0xff) / 255,
            alpha: 0.98
        )
    }
}
