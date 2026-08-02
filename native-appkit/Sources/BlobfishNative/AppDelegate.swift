import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panelController = PetPanelController()
    private var taskMonitor: TaskMonitor?
    private var statusItem: NSStatusItem?
    private var taskStatusItem: NSMenuItem?
    private var pauseItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusMenu()
        panelController.show()

        let leaseDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BlobfishDesktopPet/agent-task-leases", isDirectory: true)
        let monitor = TaskMonitor(directoryURL: leaseDirectory)
        monitor.onUpdate = { [weak self] snapshot in
            self?.panelController.update(snapshot: snapshot)
            self?.updateStatusMenu(snapshot)
        }
        taskMonitor = monitor
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        taskMonitor?.stop()
        panelController.stop()
    }

    private func configureStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🐟"
        item.button?.toolTip = "水滴鱼原生试验版"

        let menu = NSMenu()
        let heading = NSMenuItem(title: "水滴鱼 · 原生试验版", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        let status = NSMenuItem(title: "没有运行中的任务", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        taskStatusItem = status
        menu.addItem(.separator())

        let pause = NSMenuItem(title: "暂停游动", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        pauseItem = pause

        let locate = NSMenuItem(title: "把鱼移到屏幕中间", action: #selector(locatePet), keyEquivalent: "")
        locate.target = self
        menu.addItem(locate)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出水滴鱼", action: #selector(quitApplication), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    private func updateStatusMenu(_ snapshot: TaskSnapshot) {
        switch snapshot.state {
        case .idle:
            taskStatusItem?.title = "没有运行中的任务"
        case .running:
            taskStatusItem?.title = snapshot.activeCount > 1 ? "正在运行 \(snapshot.activeCount) 个任务" : "任务正在运行"
        case .waiting:
            taskStatusItem?.title = "任务正在等你确认"
        case .completed:
            taskStatusItem?.title = "任务已完成"
        case .failed:
            taskStatusItem?.title = "任务失败"
        }
    }

    @objc private func togglePause() {
        panelController.manuallyPaused.toggle()
        pauseItem?.state = panelController.manuallyPaused ? .on : .off
        pauseItem?.title = panelController.manuallyPaused ? "继续游动" : "暂停游动"
    }

    @objc private func locatePet() {
        panelController.centerOnPrimaryScreen()
        panelController.show()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}
