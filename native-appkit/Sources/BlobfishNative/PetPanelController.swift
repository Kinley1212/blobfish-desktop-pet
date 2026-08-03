import AppKit

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
    private var bobPhase: CGFloat = 0
    private var bobBaselineY: CGFloat?
    private var lastAutomaticOrigin: NSPoint?
    private var config: AppConfig
    private var speechTimer: Timer?

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
        bobBaselineY = nil
        lastAutomaticOrigin = nil
        syncMovementTimer()
    }

    func centerOnPrimaryScreen() {
        guard let visibleFrame = NSScreen.main?.visibleFrame else { return }
        let x = visibleFrame.midX - panel.frame.width / 2
        panel.setFrameOrigin(NSPoint(x: x, y: visibleFrame.minY - petView.movementBounds.minY))
        bobBaselineY = nil
        lastAutomaticOrigin = nil
    }

    func stop() {
        movementTimer?.invalidate()
        movementTimer = nil
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
        movementTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.moveOneFrame()
        }
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
        var origin = panel.frame.origin
        let step = CGFloat(config.pet.speed) * 0.84
        bobPhase += .pi / 13.5
        if bobPhase >= .pi * 2 { bobPhase -= .pi * 2 }
        let bob = (sin(bobPhase) + 1) * 2.5
        let externallyMoved = lastAutomaticOrigin.map {
            abs(origin.x - $0.x) > 1.5 || abs(origin.y - $0.y) > 1.5
        } ?? true

        if config.pet.moveAxis == "vertical", movementEnabled {
            origin.y += movementDirection * step
            if origin.y <= allowed.minY {
                origin.y = allowed.minY
                movementDirection = 1
            } else if origin.y >= allowed.maxY {
                origin.y = allowed.maxY
                movementDirection = -1
            }
            origin.x = min(max(origin.x, allowed.minX), allowed.maxX)
        } else {
            if movementEnabled, config.pet.moveAxis == "horizontal" {
                origin.x += movementDirection * step
                if origin.x <= allowed.minX {
                    origin.x = allowed.minX
                    movementDirection = 1
                } else if origin.x >= allowed.maxX {
                    origin.x = allowed.maxX
                    movementDirection = -1
                }
            }
            if externallyMoved || bobBaselineY == nil { bobBaselineY = origin.y - bob }
            origin.y = min(max((bobBaselineY ?? origin.y) + bob, allowed.minY), allowed.maxY)
            origin.x = min(max(origin.x, allowed.minX), allowed.maxX)
        }
        petView.direction = movementDirection
        panel.setFrameOrigin(origin)
        lastAutomaticOrigin = origin
    }
}
