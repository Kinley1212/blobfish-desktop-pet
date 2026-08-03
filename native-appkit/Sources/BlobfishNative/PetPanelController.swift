import AppKit

final class PetPanelController {
    let panel: NSPanel
    private let petView: PetView
    private var movementTimer: Timer?
    private var movementDirection: CGFloat = 1
    private var taskWantsMovement = false
    private var hasActiveTasks = false
    private var config: AppConfig
    private var speechTimer: Timer?

    var onClick: (() -> Void)? {
        didSet { petView.onClick = onClick }
    }

    init(runtime: AppRuntime) {
        config = runtime.config
        let size = NSSize(width: 300, height: 190)
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
        syncMovementTimer()
    }

    func centerOnPrimaryScreen() {
        guard let visibleFrame = NSScreen.main?.visibleFrame else { return }
        let x = visibleFrame.midX - panel.frame.width / 2
        panel.setFrameOrigin(NSPoint(x: x, y: visibleFrame.minY - 5))
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
        let shouldMove = ((hasActiveTasks && taskWantsMovement && config.pet.roamWhenTasks)
                || (!hasActiveTasks && config.pet.roamWhenNoTasks))
        if !shouldMove {
            movementTimer?.invalidate()
            movementTimer = nil
            return
        }
        guard movementTimer == nil else { return }
        movementTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.moveOneFrame()
        }
        RunLoop.main.add(movementTimer!, forMode: .common)
    }

    private func moveOneFrame() {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        var origin = panel.frame.origin
        let step = CGFloat(config.pet.speed) * 0.84
        if config.pet.moveAxis == "vertical" {
            origin.y += movementDirection * step
            let bounds = petView.characterBounds
            let minimumY = visibleFrame.minY - bounds.minY
            let maximumY = visibleFrame.maxY - bounds.maxY
            if origin.y <= minimumY {
                origin.y = minimumY
                movementDirection = 1
            } else if origin.y >= maximumY {
                origin.y = maximumY
                movementDirection = -1
            }
        } else {
            origin.x += movementDirection * step
            let bounds = petView.characterBounds
            let minimumX = visibleFrame.minX - bounds.minX
            let maximumX = visibleFrame.maxX - bounds.maxX
            if origin.x <= minimumX {
                origin.x = minimumX
                movementDirection = 1
            } else if origin.x >= maximumX {
                origin.x = maximumX
                movementDirection = -1
            }
            origin.y = visibleFrame.minY - petView.characterBounds.minY
        }
        petView.direction = movementDirection
        panel.setFrameOrigin(origin)
    }
}
