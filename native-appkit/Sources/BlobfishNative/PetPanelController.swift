import AppKit

final class PetPanelController {
    let panel: NSPanel
    private let petView: PetView
    private var movementTimer: Timer?
    private var movementDirection: CGFloat = 1
    private var taskWantsMovement = false

    var manuallyPaused = false {
        didSet { syncMovementTimer() }
    }

    init() {
        let size = NSSize(width: 300, height: 160)
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
        panel.title = "水滴鱼原生试验版"
        centerOnPrimaryScreen()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func update(snapshot: TaskSnapshot) {
        petView.snapshot = snapshot
        taskWantsMovement = snapshot.state == .running
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

    private func syncMovementTimer() {
        let shouldMove = taskWantsMovement && !manuallyPaused
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
        origin.x += movementDirection * 1.25
        let minimumX = visibleFrame.minX
        let maximumX = visibleFrame.maxX - panel.frame.width
        if origin.x <= minimumX {
            origin.x = minimumX
            movementDirection = 1
        } else if origin.x >= maximumX {
            origin.x = maximumX
            movementDirection = -1
        }
        origin.y = visibleFrame.minY - 5
        petView.direction = movementDirection
        panel.setFrameOrigin(origin)
    }
}
