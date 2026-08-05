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
    static func shouldPause(hovering: Bool, menuOpen: Bool, interacting: Bool, dragging: Bool) -> Bool {
        hovering || menuOpen || interacting || dragging
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

final class PetPanelController {
    let panel: NSPanel
    private let petView: PetView
    private let guestView: PetView
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
    private var lastAutomaticOrigin: NSPoint?
    private var config: AppConfig
    private var interactionTimer: Timer?
    private var interactionPaused = false
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
    private var visitPaused = false

    var onClick: (() -> Void)? {
        didSet { petView.onClick = onClick }
    }
    var onSpeechBubbleClick: (() -> Void)? {
        didSet { petView.onSpeechBubbleClick = onSpeechBubbleClick }
    }
    var onPetting: ((Int) -> Void)?
    var moodFaceProvider: ((String) -> String?)?
    private lazy var speechQueue = SpeechQueue(
        deliver: { [weak self] message in
            guard let self else { return }
            self.petView.transientMessage = message.text.isEmpty ? nil : message.text
            self.petView.transientMessageEvent = message.event
            self.petView.transientMessageColor = message.color
            self.petView.setMoodFace(message.faceID ?? message.event.flatMap { self.moodFaceProvider?($0) })
            self.show()
        },
        onIdle: { [weak self] in
            self?.petView.transientMessage = nil
            self?.petView.transientMessageEvent = nil
            self?.petView.transientMessageColor = nil
            self?.petView.setMoodFace(nil)
        }
    )

    init(runtime: AppRuntime) {
        config = runtime.config
        // The extra transparent height is reserved for a speech bubble plus the
        // four-card task carousel. Collision still uses movementBounds, so this
        // does not create an invisible wall around the pet.
        let size = NSSize(width: 340, height: 300)
        panel = PetPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        petView = PetView(frame: NSRect(origin: .zero, size: size))
        guestView = PetView(frame: NSRect(x: 168, y: 0, width: 170, height: 165))
        panel.contentView = petView
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
        petView.character = runtime.character
        petView.characterScale = config.pet.scale
        petView.accessoryPacks = runtime.accessories
        petView.accessorySpec = AppearanceJSON.accessorySpec(in: config, characterID: config.pet.characterPackId)
        petView.customization = config.pet.customization[config.pet.characterPackId]
        petView.performancePanelSide = config.performance.panelSide
        petView.performancePanelVerticalPosition = config.performance.panelVerticalPosition
        petView.onDragStart = { [weak self] in self?.beginDrag() }
        petView.onDragMove = { [weak self] dx, dy in self?.dragBy(dx: dx, dy: dy) }
        petView.onDragEnd = { [weak self] vx, vy in self?.endDrag(velocityX: vx, velocityY: vy) }
        petView.locale = config.ui.locale
        centerOnPrimaryScreen()
        syncMovementTimer()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func update(snapshot: TaskSnapshot) {
        petView.snapshot = snapshot
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
        petView.characterScale = config.pet.scale
        petView.accessoryPacks = runtime.accessories
        petView.accessorySpec = AppearanceJSON.accessorySpec(in: config, characterID: config.pet.characterPackId)
        petView.customization = config.pet.customization[config.pet.characterPackId]
        petView.performancePanelSide = config.performance.panelSide
        petView.performancePanelVerticalPosition = config.performance.panelVerticalPosition
        petView.locale = config.ui.locale
        bobBaselineY = nil
        preciseOrigin = nil
        lastFrameUptime = nil
        lastAutomaticOrigin = nil
        syncMovementTimer()
    }

    func centerOnPrimaryScreen() {
        guard let visibleFrame = NSScreen.main?.visibleFrame else { return }
        let x = visibleFrame.midX - panel.frame.width / 2
        panel.setFrameOrigin(NSPoint(x: x, y: visibleFrame.minY - petView.movementBounds.minY))
        bobBaselineY = nil
        preciseOrigin = nil
        lastFrameUptime = nil
        lastAutomaticOrigin = nil
    }

    func stop() {
        movementDisplayLink.stop()
        interactionTimer?.invalidate()
        interactionTimer = nil
        speechQueue.clear()
        panel.orderOut(nil)
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

    func playCompletionEffect(all: Bool) { petView.playCompletionEffect(all: all) }

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

    func setMenuPaused(_ paused: Bool) {
        menuPaused = paused
        if paused {
            flingVelocity = nil
            petView.updateMotion(elapsed: petView.motionElapsed, bobOffset: 0)
        }
    }

    func updateClock(state: ClockState, timerText: String?) {
        petView.alarmClockVisible = ClockAccessoryPolicy.shouldShowClock(
            state: state,
            nowMs: Date().timeIntervalSince1970 * 1_000
        )
        petView.alarmRinging = state.alerts.contains(where: { $0.state == "ringing" })
        petView.clockAlert = state.alerts.first(where: { $0.state == "ringing" })
        petView.timerText = timerText
    }

    func setClockActions(snooze: @escaping (String) -> Void, dismiss: @escaping (String) -> Void) {
        petView.onClockSnooze = snooze
        petView.onClockDismiss = dismiss
    }

    func updatePerformance(_ sample: PerformanceSample?) { petView.performanceSample = sample }

    func updateUnreadCount(_ count: Int) { petView.unreadMessageCount = count }

    func showVisit(presence: FishPresence, friendName: String, runtime: AppRuntime) {
        guard let character = try? runtime.catalog?.character(id: presence.characterPackID) else { return }
        guestView.character = character
        guestView.characterScale = min(0.82, config.pet.scale * 0.82)
        guestView.accessoryPacks = runtime.accessories
        guestView.customization = presence.customization
        guestView.accessorySpec = CharacterAccessories(presence.accessories)
        guestView.motionState = .idle
        guestView.updateMotion(elapsed: 0, bobOffset: 0)
        guestView.isHidden = false
        petView.visitingFriendName = friendName
        visitPaused = true
        flingVelocity = nil
    }

    func endVisit() {
        guestView.isHidden = true
        petView.visitingFriendName = nil
        visitPaused = false
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
            self.panel.setFrameOrigin(NSPoint(x: initialFrame.minX, y: initialFrame.minY - progress * 18))
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
        let visualBounds = petView.movementBounds
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
        let bob = PetMotionTiming.swimOffset(
            elapsed: motionElapsed,
            characterID: petView.characterID,
            state: motionState
        )
        updatePointerInteraction()
        let movementPaused = PetMovementPause.shouldPause(
            hovering: hoverPaused,
            menuOpen: menuPaused,
            interacting: interactionPaused,
            dragging: dragging
        ) || visitPaused
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
            bobOffset: movementPaused ? 0 : bob
        )

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
            petView.direction = velocity.dx >= 0 ? 1 : -1
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
        petView.direction = movementDirection
        setPanelOriginIfChanged(origin)
        preciseOrigin = origin
        bobBaselineY = origin.y
        lastAutomaticOrigin = panel.frame.origin
    }

    private func beginDrag() {
        dragging = true
        hoverPaused = false
        flingVelocity = nil
        petView.updateMotion(elapsed: petView.motionElapsed, bobOffset: 0)
        preciseOrigin = panel.frame.origin
        lastAutomaticOrigin = panel.frame.origin
    }

    private func dragBy(dx: CGFloat, dy: CGFloat) {
        guard dragging else { return }
        let visualBounds = petView.movementBounds
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
        let maximum: CGFloat = 1_833.33
        if speed > maximum {
            let scale = maximum / speed
            flingVelocity = CGVector(dx: amplified.dx * scale, dy: amplified.dy * scale)
        } else {
            flingVelocity = amplified
        }
    }

    private func updatePointerInteraction() {
        let point = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let hovering = petView.interactiveBounds.contains(point) && !dragging
        let shouldIgnoreMouse = !(hovering || dragging)
        if panel.ignoresMouseEvents != shouldIgnoreMouse {
            panel.ignoresMouseEvents = shouldIgnoreMouse
        }
        hoverPaused = hovering
        guard hovering else {
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
    }
}
