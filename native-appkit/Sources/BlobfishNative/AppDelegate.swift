import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: AppRuntime!
    private var panelController: PetPanelController!
    private var settingsController: SettingsWindowController?
    private var taskMonitor: TaskMonitor?
    private var statusItem: NSStatusItem?
    private var taskStatusItem: NSMenuItem?
    private var pauseItem: NSMenuItem?
    private var previousSnapshot = TaskSnapshot.idle
    private let soundPlayer = SoundPlayer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        runtime = AppRuntime()
        panelController = PetPanelController(runtime: runtime)
        panelController.onClick = { [weak self] in
            guard let self else { return }
            self.panelController.say(self.runtime.phrase(event: "interaction.click") ?? "……你戳我干嘛。")
        }
        configureStatusMenu()
        panelController.show()

        let leaseDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BlobfishDesktopPet/agent-task-leases", isDirectory: true)
        let monitor = TaskMonitor(directoryURL: leaseDirectory)
        monitor.includeTitles = runtime.config.privacy.includeTaskTitles
        monitor.onUpdate = { [weak self] snapshot in
            self?.handleTaskFeedback(snapshot)
            self?.panelController.update(snapshot: snapshot)
            self?.updateStatusMenu(snapshot)
        }
        taskMonitor = monitor
        monitor.start()
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        taskMonitor?.stop()
        panelController.stop()
    }

    private func configureStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🐟"
        item.button?.toolTip = "水滴鱼"

        let menu = NSMenu()
        let heading = NSMenuItem(title: "水滴鱼", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        let status = NSMenuItem(title: "没有运行中的任务", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        taskStatusItem = status
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let pause = NSMenuItem(title: "暂停游动", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        pauseItem = pause
        syncMovementMenu()

        let locate = NSMenuItem(title: "把鱼移到屏幕中间", action: #selector(locatePet), keyEquivalent: "")
        locate.target = self
        menu.addItem(locate)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出水滴鱼", action: #selector(quitApplication), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        panelController.panel.contentView?.menu = menu
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

    private func handleTaskFeedback(_ snapshot: TaskSnapshot) {
        defer { previousSnapshot = snapshot }
        let wasActive = previousSnapshot.activeCount
        let isActive = snapshot.activeCount
        if snapshot.state == .waiting && previousSnapshot.state != .waiting {
            if runtime.config.sound.needsInput.enabled {
                soundPlayer.play(id: runtime.config.sound.needsInput.soundId)
            }
            panelController.say(runtime.phrase(
                event: "agent.needsInput",
                context: ["activeCount": .number(Double(isActive))]
            ) ?? "这里要你决定。")
            panelController.playEffect(.waiting)
        } else if snapshot.state == .failed && previousSnapshot.state != .failed {
            if runtime.config.sound.taskComplete.enabled, !isQuietNow() {
                soundPlayer.play(id: runtime.config.sound.taskComplete.soundId)
            }
            panelController.say(runtime.phrase(event: "agent.failed") ?? "这个没弄成。")
            panelController.playEffect(.failed)
        } else if snapshot.state == .completed && previousSnapshot.state != .completed {
            if runtime.config.sound.taskComplete.enabled, !isQuietNow() {
                soundPlayer.play(id: runtime.config.sound.taskComplete.soundId)
            }
            panelController.say(runtime.phrase(event: "agent.allCompleted", context: ["remaining": .number(0)]) ?? "都结束了……终于。")
            panelController.playEffect(.completed)
        } else if wasActive > isActive, isActive > 0 {
            if runtime.config.sound.taskComplete.enabled, !isQuietNow() {
                soundPlayer.play(id: runtime.config.sound.taskComplete.soundId)
            }
            panelController.say(runtime.phrase(
                event: "agent.completed",
                context: ["remaining": .number(Double(isActive))]
            ) ?? "这个好了。")
            panelController.playEffect(.completed)
        } else if isActive > wasActive {
            panelController.say(runtime.phrase(
                event: "agent.started",
                context: ["activeCount": .number(Double(isActive))]
            ) ?? "又开始了……我去游。")
        }
    }

    private func isQuietNow() -> Bool {
        let quiet = runtime.config.quietHours
        guard quiet.enabled else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let current = formatter.string(from: Date())
        if quiet.start <= quiet.end { return current >= quiet.start && current < quiet.end }
        return current >= quiet.start || current < quiet.end
    }

    @objc private func togglePause() {
        do {
            try runtime.update { $0.pet.roamWhenNoTasks.toggle() }
            panelController.apply(runtime: runtime)
            syncMovementMenu()
        } catch {
            panelController.say("没能改好游动设置。")
        }
    }

    private func syncMovementMenu() {
        pauseItem?.title = runtime.config.ui.locale == "en" ? "Move while idle" : "没有任务时也继续游动"
        pauseItem?.state = runtime.config.pet.roamWhenNoTasks ? .on : .off
    }

    @objc private func locatePet() {
        panelController.centerOnPrimaryScreen()
        panelController.show()
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(runtime: runtime) { [weak self] in
                guard let self else { return }
                self.panelController.apply(runtime: self.runtime)
                self.taskMonitor?.includeTitles = self.runtime.config.privacy.includeTaskTitles
                self.syncMovementMenu()
            }
        }
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApplication() {
        let goodbye = runtime.phrase(event: "interaction.goodbye") ?? "好吧，我先沉下去了。"
        panelController.say(goodbye, duration: 1.2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.panelController.animateExit { NSApp.terminate(nil) }
        }
    }
}
