import AppKit

enum PetMotionTiming {
    static let framesPerSecond = 60.0
    static let pointsPerSecondPerSpeedUnit = 1_000.0 / 30.0
    static let swimPeriod = 0.9
    static let swimDistance = 5.0

    static func travelDistance(speed: Double, elapsed: TimeInterval) -> CGFloat {
        CGFloat(speed * pointsPerSecondPerSpeedUnit * max(0, min(elapsed, 0.05)))
    }

    static func swimOffset(elapsed: TimeInterval) -> CGFloat {
        let phase = elapsed.truncatingRemainder(dividingBy: swimPeriod) / swimPeriod
        return CGFloat((1 - cos(phase * 2 * .pi)) * swimDistance / 2)
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
}

final class PetPanelController {
    let panel: NSPanel
    private let petView: PetView
    private var movementTimer: Timer?
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
    private var speechTimer: Timer?
    private var interactionTimer: Timer?
    private var interactionPaused = false

    var onClick: (() -> Void)? {
        didSet { petView.onClick = onClick }
    }

    init(runtime: AppRuntime) {
        config = runtime.config
        // The extra transparent height is reserved for a speech bubble plus the
        // four-card task carousel. Collision still uses movementBounds, so this
        // does not create an invisible wall around the pet.
        let size = NSSize(width: 340, height: 300)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        petView = PetView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = petView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "水滴鱼"
        petView.character = runtime.character
        petView.characterScale = config.pet.scale
        petView.accessoryPacks = runtime.accessories
        petView.accessorySpec = AppearanceJSON.accessorySpec(in: config, characterID: config.pet.characterPackId)
        petView.customization = config.pet.customization[config.pet.characterPackId]
        petView.performancePetName = config.ui.locale == "en" ? "Pet" : "水滴鱼"
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
        syncMovementTimer()
    }

    func apply(runtime: AppRuntime) {
        config = runtime.config
        petView.character = runtime.character
        petView.characterScale = config.pet.scale
        petView.accessoryPacks = runtime.accessories
        petView.accessorySpec = AppearanceJSON.accessorySpec(in: config, characterID: config.pet.characterPackId)
        petView.customization = config.pet.customization[config.pet.characterPackId]
        petView.performancePetName = config.ui.locale == "en" ? "Pet" : "水滴鱼"
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
        movementTimer?.invalidate()
        movementTimer = nil
        interactionTimer?.invalidate()
        interactionTimer = nil
        panel.orderOut(nil)
    }

    func say(_ text: String, duration: TimeInterval = 7) {
        speechTimer?.invalidate()
        petView.transientMessage = text
        show()
        speechTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.petView.transientMessage = nil
            self?.speechTimer = nil
        }
        RunLoop.main.add(speechTimer!, forMode: .common)
    }

    func playEffect(_ state: TaskDisplayState) { petView.playEffect(state) }

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

    func updateClock(state: ClockState, timerText: String?) {
        petView.alarmClockVisible = state.alarms.contains(where: \.enabled)
            || state.alerts.contains(where: { $0.sourceType == "alarm" })
        petView.alarmRinging = state.alerts.contains(where: { $0.sourceType == "alarm" && $0.state == "ringing" })
        petView.timerText = timerText
    }

    func updatePerformance(_ sample: PerformanceSample?) { petView.performanceSample = sample }

    func animateExit(completion: @escaping () -> Void) {
        movementTimer?.invalidate()
        movementTimer = nil
        let initialFrame = panel.frame
        let started = Date()
        var timer: Timer?
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] value in
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
        guard movementTimer == nil else { return }
        lastFrameUptime = ProcessInfo.processInfo.systemUptime
        movementTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / PetMotionTiming.framesPerSecond, repeats: true) { [weak self] _ in
            self?.moveOneFrame()
        }
        movementTimer?.tolerance = 1.0 / 240.0
        RunLoop.main.add(movementTimer!, forMode: .common)
    }

    private func moveOneFrame() {
        let visualBounds = petView.movementBounds
        let visualCenter = NSPoint(
            x: panel.frame.minX + visualBounds.midX,
            y: panel.frame.minY + visualBounds.midY
        )
        let screen = NSScreen.screens.first { $0.frame.contains(visualCenter) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        guard let allowed = PetMovementGeometry.allowedOrigins(visibleFrame: visibleFrame, visualBounds: visualBounds) else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        let elapsed = uptime - (lastFrameUptime ?? uptime - 1.0 / PetMotionTiming.framesPerSecond)
        lastFrameUptime = uptime
        let step = PetMotionTiming.travelDistance(speed: config.pet.speed, elapsed: elapsed)
        let bob = PetMotionTiming.swimOffset(elapsed: uptime - motionStartUptime)
        let actualOrigin = panel.frame.origin
        let externallyMoved = lastAutomaticOrigin.map {
            abs(actualOrigin.x - $0.x) > 1.5 || abs(actualOrigin.y - $0.y) > 1.5
        } ?? true
        if externallyMoved || preciseOrigin == nil {
            preciseOrigin = actualOrigin
            bobBaselineY = actualOrigin.y
        }
        var origin = preciseOrigin ?? actualOrigin
        petView.visualBobOffset = interactionPaused ? 0 : bob

        if config.pet.moveAxis == "vertical", movementEnabled, !interactionPaused {
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
            if movementEnabled, !interactionPaused, config.pet.moveAxis == "horizontal" {
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
        panel.setFrameOrigin(origin)
        preciseOrigin = origin
        lastAutomaticOrigin = panel.frame.origin
    }
}
