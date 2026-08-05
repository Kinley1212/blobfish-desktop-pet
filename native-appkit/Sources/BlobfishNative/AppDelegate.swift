import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum SpeechPriority {
        static let idle = 10
        static let interaction = 30
        static let schedule = 40
        static let calendar = 50
        static let agent = 60
        static let messenger = 75
        static let urgent = 90
    }

    private let openSettingsAtLaunch: Bool
    private var runtime: AppRuntime!
    private var panelController: PetPanelController!
    private var settingsController: SettingsWindowController?
    private var dialogueController: DialogueWindowController?
    private var fishChatController: FishChatWindowController?
    private var taskMonitor: TaskMonitor?
    private var clockService: ClockService?
    private var routineService: RoutineService?
    private var calendarService: CalendarService?
    private var performanceMonitor: PerformanceMonitor?
    private var messengerService: FishMessengerService?
    private var statusItem: NSStatusItem?
    private var messengerMenuItem: NSMenuItem?
    private var pauseItem: NSMenuItem?
    private var taskRoamItem: NSMenuItem?
    private var performanceItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var clockAlertTitleItem: NSMenuItem?
    private var clockSnoozeItem: NSMenuItem?
    private var clockDismissItem: NSMenuItem?
    private var timerControlItem: NSMenuItem?
    private var quickTimerItem: NSMenuItem?
    private var previousSnapshot = TaskSnapshot.idle
    private var clickCount = 0
    private var chatInviteTimer: Timer?
    private var chatInviteUntil = Date.distantPast
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
            if Date() < self.chatInviteUntil {
                self.chatInviteUntil = .distantPast
                Task { @MainActor in self.openDialogue() }
                return
            }
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
        panelController.onUnreadBadgeClick = { [weak self] in
            self?.openFishChat()
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

        let messenger = FishMessengerService(
            supportDirectory: runtime.configStore.fileURL.deletingLastPathComponent()
        )
        messenger.addStateObserver { [weak self, weak messenger] in
            guard let self, let messenger else { return }
            self.panelController.updateUnreadCount(messenger.unreadCount)
            self.updateMessengerMenu(unreadCount: messenger.unreadCount)
            if let contactID = messenger.activeVisitContactID,
               let contact = messenger.profile?.contacts.first(where: { $0.id == contactID }),
               let presence = contact.lastPresence {
                self.panelController.showVisit(
                    presence: presence,
                    friendName: contact.nickname ?? contact.invite.displayName,
                    runtime: self.runtime
                )
            } else if messenger.activeVisitContactID == nil {
                self.panelController.endVisit()
            }
        }
        panelController.updateUnreadCount(messenger.unreadCount)
        updateMessengerMenu(unreadCount: messenger.unreadCount)
        messenger.onMessage = { [weak self, weak messenger] message, contact in
            guard let self, let messenger, !contact.muted else { return }
            if messenger.preferences.incomingSoundEnabled, !self.isQuietNow() {
                self.soundPlayer.play(id: messenger.preferences.incomingSoundID)
            }
            let kind = message.kind ?? .text
            if kind == .visitStart, messenger.preferences.visitsEnabled {
                Task { @MainActor in
                    let reply = self.runtime.config.ui.locale == "en" ? "I'm here!" : "我来啦！"
                    do {
                        try await messenger.send(
                            text: reply, to: contact.id, kind: .visitAccept,
                            presence: self.currentFishPresence()
                        )
                        self.panelController.showFriendMessage(
                            id: UUID(), text: reply,
                            color: messenger.preferences.bubbleColor,
                            speaker: .owner,
                            duration: messenger.preferences.effectiveMessageDisplaySeconds
                        )
                    } catch {
                        self.panelController.say(
                            self.runtime.config.ui.locale == "en"
                                ? "I couldn't answer the visit invitation."
                                : "刚才没能回应串门邀请。",
                            event: "messenger.error",
                            duration: 5,
                            priority: SpeechPriority.interaction,
                            replaceKey: "messenger.visitAccept.error"
                        )
                    }
                }
            }
            self.panelController.playEffect(.completed)
            switch kind {
            case .text:
                let visiting = messenger.activeVisitContactID == contact.id
                self.panelController.showFriendMessage(
                    id: message.id,
                    text: visiting ? message.text : "\(message.senderName)：\(message.text)",
                    color: message.bubbleColor,
                    speaker: visiting ? .visitor : .owner,
                    duration: messenger.preferences.effectiveMessageDisplaySeconds
                )
            case .visitStart, .visitAccept:
                self.panelController.showFriendMessage(
                    id: message.id,
                    text: message.text,
                    color: message.bubbleColor,
                    speaker: .visitor,
                    duration: messenger.preferences.effectiveMessageDisplaySeconds
                )
            case .visitEnd:
                self.panelController.say(
                    "\(message.senderName) 回家啦，下次再玩。",
                    event: "messenger.visitEnd",
                    duration: 5,
                    priority: SpeechPriority.messenger,
                    replaceKey: "messenger.\(message.id.uuidString)",
                    color: message.bubbleColor
                )
            }
        }
        messenger.onError = { [weak self] _ in
            guard let self else { return }
            self.panelController.say(
                self.runtime.config.ui.locale == "en" ? "I couldn't reach your friend's fish." : "刚才没联系上朋友的鱼。",
                event: "messenger.error",
                duration: 5,
                priority: SpeechPriority.interaction,
                replaceKey: "messenger.error"
            )
        }
        messengerService = messenger
        messenger.start()

        let supportDirectory = runtime.configStore.fileURL.deletingLastPathComponent()
        let clocks = ClockService(directoryURL: supportDirectory)
        panelController.setClockActions(
            snooze: { [weak clocks] id in try? clocks?.snoozeAlert(id: id, minutes: 5) },
            dismiss: { [weak clocks] id in try? clocks?.dismissAlert(id: id) }
        )
        clocks.workdays = runtime.config.schedule.workdays
        clocks.onTick = { [weak self] state, text in
            self?.panelController.updateClock(state: state, timerText: text)
            self?.updateClockMenu(state)
        }
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
        }
        taskMonitor = monitor
        monitor.start()
        scheduleChatInvite()
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
        messengerService?.stop()
        chatInviteTimer?.invalidate()
        panelController?.stop()
    }

    private func configureStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🐟"
        item.button?.toolTip = "水滴鱼"

        let menu = NSMenu()
        menu.delegate = self

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let chat = NSMenuItem(title: "找水滴鱼聊天…", action: #selector(openDialogue), keyEquivalent: "")
        chat.target = self
        menu.addItem(chat)

        let messages = NSMenuItem(title: "消息", action: #selector(openFishChat), keyEquivalent: "")
        messages.target = self
        menu.addItem(messages)
        messengerMenuItem = messages

        let taskRoam = NSMenuItem(title: "任务进行时游动", action: #selector(toggleTaskRoam), keyEquivalent: "")
        taskRoam.target = self
        menu.addItem(taskRoam)
        taskRoamItem = taskRoam

        let pause = NSMenuItem(title: "没有任务时也继续游动", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        pauseItem = pause

        let performance = NSMenuItem(title: "显示性能面板", action: #selector(togglePerformancePanel), keyEquivalent: "")
        performance.target = self
        menu.addItem(performance)
        performanceItem = performance

        let launch = NSMenuItem(title: "登录后自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        menu.addItem(launch)
        launchAtLoginItem = launch
        syncQuickSettingsMenu()

        let locate = NSMenuItem(title: "把鱼移到屏幕中间", action: #selector(locatePet), keyEquivalent: "")
        locate.target = self
        menu.addItem(locate)
        let alertTitle = NSMenuItem(title: "时间到了", action: nil, keyEquivalent: "")
        alertTitle.isEnabled = false
        alertTitle.isHidden = true
        menu.addItem(alertTitle)
        clockAlertTitleItem = alertTitle
        let snooze = NSMenuItem(title: "稍后 5 分钟", action: #selector(snoozeClockAlert), keyEquivalent: "")
        snooze.target = self; snooze.isHidden = true; menu.addItem(snooze); clockSnoozeItem = snooze
        let dismiss = NSMenuItem(title: "知道了", action: #selector(dismissFirstClockAlert), keyEquivalent: "")
        dismiss.target = self; dismiss.isHidden = true; menu.addItem(dismiss); clockDismissItem = dismiss

        let timerControl = NSMenuItem(title: "计时器", action: nil, keyEquivalent: "")
        timerControl.isHidden = true
        menu.addItem(timerControl)
        timerControlItem = timerControl

        let quickTimer = NSMenuItem(title: "快速计时", action: nil, keyEquivalent: "")
        let quickMenu = NSMenu()
        for minutes in [5, 15, 25, 45] {
            let title = minutes == 25 ? "25 分钟专注" : "\(minutes) 分钟"
            let option = NSMenuItem(title: title, action: #selector(startQuickTimer(_:)), keyEquivalent: "")
            option.target = self; option.representedObject = minutes; quickMenu.addItem(option)
        }
        quickTimer.submenu = quickMenu
        menu.addItem(quickTimer)
        quickTimerItem = quickTimer
        let clocks = NSMenuItem(title: "闹钟与计时器…", action: #selector(openClocks), keyEquivalent: "")
        clocks.target = self; menu.addItem(clocks)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出水滴鱼", action: #selector(quitApplication), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        panelController.panel.contentView?.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        panelController?.setMenuPaused(true)
    }

    func menuDidClose(_ menu: NSMenu) {
        panelController?.setMenuPaused(false)
    }

    private func updateMessengerMenu(unreadCount: Int) {
        let title = runtime.config.ui.locale == "en" ? "Messages" : "消息"
        messengerMenuItem?.title = unreadCount > 0
            ? "\(title) · \(unreadCount > 99 ? "99+" : String(unreadCount))"
            : title
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
            panelController.playCompletionEffect(all: true)
        } else if wasActive > isActive, isActive > 0 {
            if runtime.config.sound.taskComplete.enabled, !isQuietNow() {
                soundPlayer.play(id: runtime.config.sound.taskComplete.soundId)
            }
            panelController.say(runtime.phrase(
                event: "agent.completed",
                context: ["remaining": .number(Double(isActive))]
            ) ?? "这个好了。", event: "agent.completed", priority: SpeechPriority.agent, replaceKey: "agent.completed")
            panelController.playCompletionEffect(all: false)
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

    private func scheduleChatInvite() {
        chatInviteTimer?.invalidate()
        let delay = Double.random(in: 25 * 60...55 * 60)
        chatInviteTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.chatInviteTimer = nil
            defer { self.scheduleChatInvite() }
            guard self.previousSnapshot.activeCount == 0,
                  self.settingsController?.window?.isVisible != true,
                  self.dialogueController?.window?.isVisible != true,
                  self.clockService?.state.alerts.contains(where: { $0.state == "ringing" }) != true,
                  !self.isQuietNow(),
                  Double.random(in: 0..<1) < 0.5 else { return }
            let lines = self.runtime.config.ui.locale == "en"
                ? ["…Got a minute?", "Want to talk for a bit?", "Hey… busy?", "I am bored. Talk?"]
                : ["……有空吗。", "陪我说会儿话？", "喂……在忙吗。", "有点无聊。要不聊聊？"]
            self.chatInviteUntil = Date().addingTimeInterval(9)
            self.panelController.say(
                lines.randomElement()!,
                event: "interaction.chatInvite",
                faceID: "face-coy",
                duration: 9,
                priority: SpeechPriority.idle,
                replaceKey: "interaction.chatInvite"
            )
        }
        RunLoop.main.add(chatInviteTimer!, forMode: .common)
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
            panelController.playCompletionEffect(all: false)
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
            syncQuickSettingsMenu()
        } catch {
            panelController.say("没能改好游动设置。", event: "system.error", duration: 5.5, priority: SpeechPriority.urgent, replaceKey: "system.error")
        }
    }

    @objc private func toggleTaskRoam() {
        updateQuickSetting(event: "interaction.taskRoamToggle") { $0.pet.roamWhenTasks.toggle() }
    }

    @objc private func togglePerformancePanel() {
        updateQuickSetting(event: "interaction.performancePanelToggle") { $0.performance.panelEnabled.toggle() }
        if !runtime.config.performance.panelEnabled { panelController.updatePerformance(nil) }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try runtime.update { $0.startup.launchAtLogin.toggle() }
            try LoginItemController.sync(enabled: runtime.config.startup.launchAtLogin)
            syncQuickSettingsMenu()
        } catch {
            panelController.say("开机启动设置没有改成功。", event: "system.error", duration: 5.5, priority: SpeechPriority.urgent, replaceKey: "system.error")
        }
    }

    private func updateQuickSetting(event: String, change: (inout AppConfig) -> Void) {
        do {
            try runtime.update(change)
            panelController.apply(runtime: runtime)
            syncQuickSettingsMenu()
            if let phrase = runtime.phrase(event: event) {
                panelController.say(phrase, event: event, priority: SpeechPriority.interaction, replaceKey: event)
            }
        } catch {
            panelController.say("设置没有改成功。", event: "system.error", duration: 5.5, priority: SpeechPriority.urgent, replaceKey: "system.error")
        }
    }

    private func syncQuickSettingsMenu() {
        pauseItem?.title = runtime.config.ui.locale == "en" ? "Move while idle" : "没有任务时也继续游动"
        pauseItem?.state = runtime.config.pet.roamWhenNoTasks ? .on : .off
        taskRoamItem?.title = runtime.config.ui.locale == "en" ? "Move while tasks run" : "任务进行时游动"
        taskRoamItem?.state = runtime.config.pet.roamWhenTasks ? .on : .off
        performanceItem?.title = runtime.config.ui.locale == "en" ? "Show performance panel" : "显示性能面板"
        performanceItem?.state = runtime.config.performance.panelEnabled ? .on : .off
        launchAtLoginItem?.title = runtime.config.ui.locale == "en" ? "Open at login" : "登录后自动启动"
        launchAtLoginItem?.state = runtime.config.startup.launchAtLogin ? .on : .off
    }

    private func enabledProviders() -> Set<String> {
        var providers = Set<String>()
        if runtime.config.integrations.codex { providers.insert("codex") }
        if runtime.config.integrations.claudeCode { providers.insert("claude-code") }
        return providers
    }

    @MainActor private func currentFishPresence() -> FishPresence {
        FishPresence(
            characterPackID: runtime.config.pet.characterPackId,
            customization: runtime.config.pet.customization[runtime.config.pet.characterPackId],
            accessories: runtime.config.pet.accessories[runtime.config.pet.characterPackId]
        )
    }

    @objc private func locatePet() {
        panelController.centerOnPrimaryScreen()
        panelController.show()
    }

    @objc private func startQuickTimer(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        let label = minutes == 25 ? (runtime.config.ui.locale == "en" ? "Focus" : "专注") : ""
        do {
            try clockService?.startTimer(minutes: minutes, label: label, source: ClockTimerSource.quick)
            panelController.say("计时开始了。", event: "clock.timerStarted", priority: SpeechPriority.schedule, replaceKey: "clock.control")
        }
        catch { panelController.say("计时器没能开始。", event: "system.error", duration: 5.5, priority: SpeechPriority.urgent, replaceKey: "system.error") }
    }

    private func updateClockMenu(_ state: ClockState) {
        let english = runtime.config.ui.locale == "en"
        let ringing = state.alerts.first(where: { $0.state == "ringing" })
        clockAlertTitleItem?.isHidden = ringing == nil
        clockSnoozeItem?.isHidden = ringing == nil
        clockDismissItem?.isHidden = ringing == nil
        if let ringing {
            let icon = ringing.sourceType == "alarm" ? "⏰" : "⏱"
            clockAlertTitleItem?.title = "\(icon) \(ringing.label.isEmpty ? (english ? "Time is up" : "时间到了") : ringing.label)"
            clockSnoozeItem?.title = english ? "Snooze 5 minutes" : "稍后 5 分钟"
            clockDismissItem?.title = english ? "Dismiss" : "知道了"
        }

        timerControlItem?.isHidden = state.timer == nil
        quickTimerItem?.isHidden = state.timer != nil
        guard let timer = state.timer else { return }
        timerControlItem?.title = "\(english ? "Timer" : "计时器") · \(clockService?.remainingTimerText() ?? "00:00")"
        let submenu = NSMenu()
        let pause = NSMenuItem(
            title: timer.state == "running"
                ? (english ? "Pause timer" : "暂停计时")
                : (english ? "Resume timer" : "继续计时"),
            action: #selector(pauseOrResumeTimer),
            keyEquivalent: ""
        )
        pause.target = self; submenu.addItem(pause)
        let extend = NSMenuItem(title: english ? "Add 5 minutes" : "增加 5 分钟", action: #selector(extendTimer), keyEquivalent: "")
        extend.target = self; submenu.addItem(extend)
        let cancel = NSMenuItem(title: english ? "Cancel timer" : "取消计时", action: #selector(cancelTimer), keyEquivalent: "")
        cancel.target = self; submenu.addItem(cancel)
        timerControlItem?.submenu = submenu
    }

    @objc private func snoozeClockAlert() {
        guard let id = clockService?.state.alerts.first(where: { $0.state == "ringing" })?.id else { return }
        do { try clockService?.snoozeAlert(id: id, minutes: 5) }
        catch { panelController.say("稍后提醒没有设好。", event: "system.error", duration: 5.5, priority: SpeechPriority.urgent, replaceKey: "system.error") }
    }

    @objc private func dismissFirstClockAlert() {
        guard let id = clockService?.state.alerts.first(where: { $0.state == "ringing" })?.id else { return }
        do { try clockService?.dismissAlert(id: id) }
        catch { panelController.say("提醒没有关掉。", event: "system.error", duration: 5.5, priority: SpeechPriority.urgent, replaceKey: "system.error") }
    }

    @objc private func pauseOrResumeTimer() {
        do {
            if clockService?.state.timer?.state == "running" { try clockService?.pauseTimer() }
            else { try clockService?.resumeTimer() }
        } catch { panelController.say("计时器没有改好。", event: "system.error", duration: 5.5, priority: SpeechPriority.urgent, replaceKey: "system.error") }
    }

    @objc private func extendTimer() {
        do { try clockService?.extendTimer(minutes: 5) }
        catch { panelController.say("计时器没有延长。", event: "system.error", duration: 5.5, priority: SpeechPriority.urgent, replaceKey: "system.error") }
    }

    @objc private func cancelTimer() {
        do { try clockService?.cancelTimer() }
        catch { panelController.say("计时器没有取消。", event: "system.error", duration: 5.5, priority: SpeechPriority.urgent, replaceKey: "system.error") }
    }

    @objc private func openClocks() { openSettings(); settingsController?.select(.clocks) }

    @MainActor @objc private func openFishChat() {
        guard let messenger = messengerService else { return }
        if fishChatController == nil {
            fishChatController = FishChatWindowController(
                messengerService: messenger,
                locale: runtime.config.ui.locale,
                presenceProvider: { [weak self] in self?.currentFishPresence() },
                onSent: { [weak self, weak messenger] text, _ in
                    guard let self, let messenger else { return }
                    self.panelController.playEffect(.completed)
                    self.panelController.showFriendMessage(
                        id: UUID(),
                        text: text,
                        color: messenger.preferences.bubbleColor,
                        speaker: .owner,
                        duration: messenger.preferences.effectiveMessageDisplaySeconds
                    )
                }
            )
        }
        fishChatController?.showWindow(nil)
        fishChatController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor @objc private func openDialogue() {
        if let window = dialogueController?.window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let catalog = runtime.catalog else {
            panelController.say("聊天内容没有加载好。", event: "system.error", duration: 5.5, priority: SpeechPriority.urgent, replaceKey: "system.error")
            return
        }
        let pack = (try? catalog.dialogue(id: runtime.config.language.packId))
            ?? (try? catalog.dialogue(id: "blobfish-zh-TW"))
        guard let pack else {
            panelController.say("聊天内容没有加载好。", event: "system.error", duration: 5.5, priority: SpeechPriority.urgent, replaceKey: "system.error")
            return
        }
        let controller = DialogueWindowController(runtime: runtime, pack: pack) { [weak self] text, face in
            self?.panelController.say(
                text,
                event: "interaction.chat",
                faceID: face,
                duration: 3.2,
                priority: SpeechPriority.interaction,
                replaceKey: "interaction.chat"
            )
        }
        dialogueController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                runtime: runtime, clockService: clockService, messengerService: messengerService,
                presenceProvider: { [weak self] in self?.currentFishPresence() }
            ) { [weak self] in
                guard let self else { return }
                self.panelController.apply(runtime: self.runtime)
                self.taskMonitor?.includeTitles = self.runtime.config.privacy.includeTaskTitles
                self.taskMonitor?.enabledProviders = self.enabledProviders()
                self.clockService?.workdays = self.runtime.config.schedule.workdays
                self.syncQuickSettingsMenu()
                Task { @MainActor in
                    self.updateMessengerMenu(unreadCount: self.messengerService?.unreadCount ?? 0)
                }
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
