import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum SpeechPriority {
        static let idle = 10
        static let interaction = 30
        static let schedule = 40
        static let calendar = 50
        static let agent = 60
        static let urgent = 90
    }

    private let openSettingsAtLaunch: Bool
    private var runtime: AppRuntime!
    private var panelController: PetPanelController!
    private var settingsController: SettingsWindowController?
    private var taskMonitor: TaskMonitor?
    private var clockService: ClockService?
    private var routineService: RoutineService?
    private var calendarService: CalendarService?
    private var performanceMonitor: PerformanceMonitor?
    private var statusItem: NSStatusItem?
    private var taskStatusItem: NSMenuItem?
    private var pauseItem: NSMenuItem?
    private var previousSnapshot = TaskSnapshot.idle
    private var clickCount = 0
    private let soundPlayer = SoundPlayer()
    private let instanceGuard = SingleInstanceGuard()

    init(openSettingsAtLaunch: Bool = false) {
        self.openSettingsAtLaunch = openSettingsAtLaunch
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        runtime = AppRuntime()
        guard instanceGuard.acquire(in: runtime.configStore.fileURL.deletingLastPathComponent()) else {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.blobfish.desktop-pet.native")
                .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?
                .activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
            return
        }
        panelController = PetPanelController(runtime: runtime)
        panelController.moodFaceProvider = { [weak self] event in
            guard let self else { return nil }
            let available = Set(self.runtime.accessories
                .filter { $0.manifest.slot == "face" }
                .map(\.id))
            return ExpressionMoodSelector.pick(event: event, available: available)
        }
        panelController.onClick = { [weak self] in
            guard let self else { return }
            self.clickCount += 1
            self.panelController.playClickReaction()
            self.panelController.say(
                self.runtime.phrase(
                    event: "interaction.click",
                    context: ["clickCount": .number(Double(self.clickCount))]
                ) ?? "……你戳我干嘛。",
                event: "interaction.click",
                duration: 0.8,
                priority: SpeechPriority.interaction,
                replaceKey: "interaction.click"
            )
            if self.runtime.config.language.rareEnabled,
               self.clickCount >= 10,
               Double.random(in: 0..<1) < 0.12,
               let rare = self.runtime.phrase(
                   event: "rare.tooManyClicks",
                   context: ["clickCount": .number(Double(self.clickCount))]
               ) {
                self.panelController.say(
                    rare,
                    event: "rare.tooManyClicks",
                    duration: 4.2,
                    priority: SpeechPriority.interaction,
                    replaceKey: "rare.tooManyClicks"
                )
            }
        }
        panelController.onPetting = { [weak self] streak in
            guard let self else { return }
            let events = (streak >= 6 ? ["interaction.pettingLots"] : [])
                + (streak >= 3 ? ["interaction.pettingMore"] : [])
                + ["interaction.petting"]
            for event in events {
                if let phrase = self.runtime.phrase(
                    event: event,
                    context: ["count": .number(Double(streak))]
                ) {
                    self.panelController.say(
                        phrase,
                        event: event,
                        duration: 2.6,
                        priority: SpeechPriority.interaction,
                        replaceKey: event
                    )
                    break
                }
            }
        }
        configureStatusMenu()
        panelController.show()

        let supportDirectory = runtime.configStore.fileURL.deletingLastPathComponent()
        let clocks = ClockService(directoryURL: supportDirectory)
        clocks.workdays = runtime.config.schedule.workdays
        clocks.onTick = { [weak self] state, text in self?.panelController.updateClock(state: state, timerText: text) }
        clocks.onEvent = { [weak self] event, state in self?.handleClockEvent(event, state: state) }
        clockService = clocks
        clocks.start()

        let routine = RoutineService(runtime: runtime)
        routine.onPhrase = { [weak self] event, context in self?.deliverPhrase(event: event, context: context) }
        routineService = routine
        routine.start()

        let calendar = CalendarService(runtime: runtime)
        calendar.onPhrase = { [weak self] event, context in self?.deliverPhrase(event: event, context: context) }
        calendarService = calendar
        calendar.start()

        let performance = PerformanceMonitor()
        performance.memoryLimitMB = runtime.config.performance.memoryLimitMb
        performance.autoQuitEnabled = runtime.config.performance.autoQuitEnabled
        performance.onSample = { [weak self] sample in
            guard let self else { return }
            self.panelController.updatePerformance(self.runtime.config.performance.panelEnabled ? sample : nil)
        }
        performance.onSustainedMemoryLimit = { [weak self] in self?.handleSustainedMemoryLimit() }
        performanceMonitor = performance
        performance.start()

        let leaseDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BlobfishDesktopPet/agent-task-leases", isDirectory: true)
        let monitor = TaskMonitor(directoryURL: leaseDirectory)
        monitor.includeTitles = runtime.config.privacy.includeTaskTitles
        monitor.enabledProviders = enabledProviders()
        monitor.onUpdate = { [weak self] snapshot in
            self?.handleTaskFeedback(snapshot)
            self?.routineService?.hasActiveTasks = snapshot.activeCount > 0
            self?.panelController.update(snapshot: snapshot)
            self?.updateStatusMenu(snapshot)
        }
        taskMonitor = monitor
        monitor.start()
        if openSettingsAtLaunch {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        taskMonitor?.stop()
        clockService?.stop()
        routineService?.stop()
        calendarService?.stop()
        performanceMonitor?.stop()
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
        let quickTimer = NSMenuItem(title: "快速计时", action: nil, keyEquivalent: "")
        let quickMenu = NSMenu()
        for minutes in [10, 25, 45] {
            let option = NSMenuItem(title: "\(minutes) 分钟", action: #selector(startQuickTimer(_:)), keyEquivalent: "")
            option.target = self; option.representedObject = minutes; quickMenu.addItem(option)
        }
        quickTimer.submenu = quickMenu
        menu.addItem(quickTimer)
        let clocks = NSMenuItem(title: "闹钟与计时器…", action: #selector(openClocks), keyEquivalent: "")
        clocks.target = self; menu.addItem(clocks)
        let dismiss = NSMenuItem(title: "停止响铃", action: #selector(dismissClockAlerts), keyEquivalent: "")
        dismiss.target = self; menu.addItem(dismiss)
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
            taskStatusItem?.title = snapshot.activeCount > 1
                ? "正在运行 \(snapshot.activeCount) 个 · \(snapshot.tasks.first?.title ?? "任务")"
                : "进行中 · \(snapshot.tasks.first?.title ?? "任务")"
        case .waiting:
            taskStatusItem?.title = "等待确认 · \(snapshot.tasks.first?.title ?? "任务")"
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
            ) ?? "这里要你决定。", event: "agent.needsInput", priority: SpeechPriority.urgent, replaceKey: "agent.needsInput")
            panelController.playEffect(.waiting)
        } else if snapshot.state == .failed && previousSnapshot.state != .failed {
            if runtime.config.sound.taskComplete.enabled, !isQuietNow() {
                soundPlayer.play(id: runtime.config.sound.taskComplete.soundId)
            }
            panelController.say(runtime.phrase(event: "agent.failed") ?? "这个没弄成。", event: "agent.failed", priority: SpeechPriority.urgent, replaceKey: "agent.failed")
            panelController.playEffect(.failed)
        } else if snapshot.state == .completed && previousSnapshot.state != .completed {
            if runtime.config.sound.taskComplete.enabled, !isQuietNow() {
                soundPlayer.play(id: runtime.config.sound.taskComplete.soundId)
            }
            panelController.say(runtime.phrase(event: "agent.allCompleted", context: ["remaining": .number(0)]) ?? "都结束了……终于。", event: "agent.allCompleted", priority: SpeechPriority.agent, replaceKey: "agent.allCompleted")
            panelController.playEffect(.completed)
        } else if wasActive > isActive, isActive > 0 {
            if runtime.config.sound.taskComplete.enabled, !isQuietNow() {
                soundPlayer.play(id: runtime.config.sound.taskComplete.soundId)
            }
            panelController.say(runtime.phrase(
                event: "agent.completed",
                context: ["remaining": .number(Double(isActive))]
            ) ?? "这个好了。", event: "agent.completed", priority: SpeechPriority.agent, replaceKey: "agent.completed")
            panelController.playEffect(.completed)
        } else if isActive > wasActive {
            panelController.say(runtime.phrase(
                event: "agent.started",
                context: ["activeCount": .number(Double(isActive))]
            ) ?? "又开始了……我去游。", event: "agent.started", priority: SpeechPriority.agent, replaceKey: "agent.started")
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

    private func handleClockEvent(_ event: ClockEvent, state: ClockState) {
        panelController.updateClock(state: state, timerText: clockService?.remainingTimerText())
        switch event {
        case .alarmDue(let alert):
            if state.preferences.alarmSound.enabled,
               state.preferences.allowSoundDuringQuietHours || !isQuietNow() {
                soundPlayer.play(id: state.preferences.alarmSound.soundId)
            }
            panelController.say(runtime.phrase(
                event: "clock.alarmRinging",
                context: alert.label.isEmpty ? [:] : ["label": .string(alert.label)]
            ) ?? (alert.label.isEmpty ? "闹钟响了。" : "\(alert.label) 到时间了。"), event: "clock.alarmRinging", priority: SpeechPriority.urgent, replaceKey: "clock.ringing")
        case .timerDue(let alert):
            if state.preferences.timerSound.enabled,
               state.preferences.allowSoundDuringQuietHours || !isQuietNow() {
                soundPlayer.play(id: state.preferences.timerSound.soundId)
            }
            panelController.say(runtime.phrase(
                event: "clock.timerCompleted",
                context: alert.label.isEmpty ? [:] : ["label": .string(alert.label)]
            ) ?? "计时结束了。", event: "clock.timerCompleted", priority: SpeechPriority.urgent, replaceKey: "clock.ringing")
            panelController.playEffect(.completed)
        case .changed(let reason):
            let eventName: String?
            switch reason {
            case "alarm-created": eventName = "clock.alarmClockAppeared"
            case "alarm-deleted": eventName = state.alarms.contains(where: \.enabled) ? nil : "clock.alarmClockDisappeared"
            case "timer-started": eventName = "clock.timerStarted"
            case "timer-paused": eventName = "clock.timerPaused"
            case "timer-resumed": eventName = "clock.timerResumed"
            case "timer-extended": eventName = "clock.timerExtended"
            case "timer-cancelled": eventName = "clock.timerCancelled"
            default: eventName = nil
            }
            if let eventName, let phrase = runtime.phrase(event: eventName) {
                panelController.say(phrase, event: eventName, priority: SpeechPriority.schedule, replaceKey: "clock.control")
            }
        }
    }

    private func deliverPhrase(event: String, context: [String: JSONValue]) {
        if event.hasPrefix("schedule."), !runtime.config.language.categories.schedule { return }
        if event.hasPrefix("system."), !runtime.config.language.categories.system { return }
        if event.hasPrefix("calendar."), !runtime.config.language.categories.calendar { return }
        if event.hasPrefix("clock."), !runtime.config.language.categories.clock { return }
        guard let phrase = runtime.phrase(event: event, context: context) else { return }
        let priority = event.hasPrefix("calendar.") ? SpeechPriority.calendar
            : event.hasPrefix("system.") ? SpeechPriority.urgent
            : SpeechPriority.schedule
        panelController.say(
            phrase,
            event: event,
            duration: event == "calendar.starting" ? 7 : 5.5,
            priority: priority,
            replaceKey: event
        )
    }

    private func handleSustainedMemoryLimit() {
        guard previousSnapshot.activeCount == 0,
              settingsController?.window?.isVisible != true,
              clockService?.state.alerts.isEmpty != false else { return }
        panelController.say(runtime.phrase(event: "system.memoryExit") ?? "内存一直太高。我先沉下去。", event: "system.memoryExit", duration: 5, priority: SpeechPriority.urgent, replaceKey: "system.memoryExit")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.panelController.animateExit { NSApp.terminate(nil) }
        }
    }

    @objc private func togglePause() {
        do {
            try runtime.update { $0.pet.roamWhenNoTasks.toggle() }
            panelController.apply(runtime: runtime)
            syncMovementMenu()
        } catch {
            panelController.say("没能改好游动设置。", event: "system.error", duration: 5.5, priority: SpeechPriority.urgent, replaceKey: "system.error")
        }
    }

    private func syncMovementMenu() {
        pauseItem?.title = runtime.config.ui.locale == "en" ? "Move while idle" : "没有任务时也继续游动"
        pauseItem?.state = runtime.config.pet.roamWhenNoTasks ? .on : .off
    }

    private func enabledProviders() -> Set<String> {
        var providers = Set<String>()
        if runtime.config.integrations.codex { providers.insert("codex") }
        if runtime.config.integrations.claudeCode { providers.insert("claude-code") }
        return providers
    }

    @objc private func locatePet() {
        panelController.centerOnPrimaryScreen()
        panelController.show()
    }

    @objc private func startQuickTimer(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        do { try clockService?.startTimer(minutes: minutes, label: ""); panelController.say("计时开始了。", event: "clock.timerStarted", priority: SpeechPriority.schedule, replaceKey: "clock.control") }
        catch { panelController.say("计时器没能开始。", event: "system.error", duration: 5.5, priority: SpeechPriority.urgent, replaceKey: "system.error") }
    }

    @objc private func dismissClockAlerts() { try? clockService?.dismissAlerts() }

    @objc private func openClocks() { openSettings(); settingsController?.select(.clocks) }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(runtime: runtime, clockService: clockService) { [weak self] in
                guard let self else { return }
                self.panelController.apply(runtime: self.runtime)
                self.taskMonitor?.includeTitles = self.runtime.config.privacy.includeTaskTitles
                self.taskMonitor?.enabledProviders = self.enabledProviders()
                self.clockService?.workdays = self.runtime.config.schedule.workdays
                self.syncMovementMenu()
                self.performanceMonitor?.memoryLimitMB = self.runtime.config.performance.memoryLimitMb
                self.performanceMonitor?.autoQuitEnabled = self.runtime.config.performance.autoQuitEnabled
                if !self.runtime.config.performance.panelEnabled { self.panelController.updatePerformance(nil) }
                self.calendarService?.stop()
                self.calendarService?.start()
                do { try LoginItemController.sync(enabled: self.runtime.config.startup.launchAtLogin) }
                catch { self.panelController.say("开机启动设置没有改成功。", event: "system.error", duration: 5.5, priority: SpeechPriority.urgent, replaceKey: "system.error") }
            }
        }
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApplication() {
        let goodbye = runtime.phrase(event: "interaction.goodbye") ?? "好吧，我先沉下去了。"
        panelController.say(goodbye, event: "interaction.goodbye", duration: 1.2, priority: SpeechPriority.interaction, replaceKey: "interaction.goodbye")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.panelController.animateExit { NSApp.terminate(nil) }
        }
    }
}
