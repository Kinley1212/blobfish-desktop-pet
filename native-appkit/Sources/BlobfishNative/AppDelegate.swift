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
    private var clockQuickController: ClockQuickWindowController?
    private var dialogueController: DialogueWindowController?
    private var fishChatController: FishChatWindowController?
    private var fishMessageComposeController: FishMessageComposeWindowController?
    private var taskMonitor: TaskMonitor?
    private var clockService: ClockService?
    private var routineService: RoutineService?
    private var calendarService: CalendarService?
    private var performanceMonitor: PerformanceMonitor?
    private var messengerService: FishMessengerService?
    private var statusItem: NSStatusItem?
    private var messengerMenuItem: NSMenuItem?
    private var messengerSendMenuItem: NSMenuItem?
    private var fishStatusMenuItem: NSMenuItem?
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
    private var lastActiveVisitContactID: UUID?
    private var visitIdleSpokenContactID: UUID?
    private let friendHitBubbleID = UUID()
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
        panelController.onDoubleClick = nil
        panelController.onRightDoubleClick = { [weak self] in
            Task { @MainActor in self?.openFishMessageComposer() }
        }
        panelController.onSceneAnchorChanged = { [weak self] sceneAnchor in
            guard let controller = self?.fishMessageComposeController,
                  controller.window?.isVisible == true else { return }
            Task { @MainActor in
                controller.updateSceneAnchor(sceneAnchor)
            }
        }
        panelController.onUnreadBadgeClick = { [weak self] in
            Task { @MainActor in self?.openFishMessageComposerForUnread() }
        }
        panelController.onCompanionClick = { [weak self] in
            guard let self,
                  let messenger = self.messengerService,
                  let contactID = messenger.activeVisitContactID,
                  let contact = messenger.profile?.contacts.first(where: { $0.id == contactID }) else { return }
            self.panelController.playCompanionHitReaction()
            let phrase = self.runtime.phrase(event: "messenger.friendHit")
                ?? (self.runtime.config.ui.locale == "en" ? "Hey! Why did you hit me?" : "喂！怎麼還打串門的小魚呀！")
            if messenger.preferences.currentStatus != .doNotDisturb {
                self.panelController.showFriendMessage(
                    id: self.friendHitBubbleID, contactID: contact.id, text: phrase,
                    color: "#FFFFFF", speaker: .visitor, duration: 6
                )
            }
        }
        panelController.onSpeechBubbleClick = { [weak self] contactID in
            Task { @MainActor in self?.presentFishMessageComposer(preferredContactID: contactID) }
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
            self.panelController.updateUnreadCount(
                self.visibleUnreadCount(messenger),
                indicatorID: messenger.preferences.effectiveMessageIndicatorID
            )
            self.updateMessengerMenu(unreadCount: messenger.unreadCount)
            let status = messenger.preferences.currentStatus
            self.panelController.setStatusAppearance(
                faceID: status.map { messenger.preferences.faceID(for: $0) },
                accessoryID: status.flatMap { messenger.preferences.accessoryID(for: $0) },
                accessories: status.flatMap { messenger.preferences.statusAccessorySpecs?[$0.rawValue] },
                customization: self.runtime.config.pet.customization[self.runtime.config.pet.characterPackId]
            )
            if let contactID = messenger.activeVisitContactID,
               let contact = messenger.profile?.contacts.first(where: { $0.id == contactID }),
               let presence = contact.lastPresence {
                if self.lastActiveVisitContactID != contactID {
                    self.lastActiveVisitContactID = contactID
                    self.visitIdleSpokenContactID = nil
                }
                self.panelController.showVisit(
                    presence: presence,
                    friendName: contact.nickname ?? contact.invite.displayName,
                    runtime: self.runtime
                )
            } else if messenger.activeVisitContactID == nil {
                self.lastActiveVisitContactID = nil
                self.visitIdleSpokenContactID = nil
                self.panelController.endVisit()
            }
        }
        panelController.updateUnreadCount(
            visibleUnreadCount(messenger),
            indicatorID: messenger.preferences.effectiveMessageIndicatorID
        )
        updateMessengerMenu(unreadCount: messenger.unreadCount)
        messenger.onMessage = { [weak self, weak messenger] message, contact in
            guard let self, let messenger, !contact.muted else { return }
            let kind = message.kind ?? .text
            if kind != .status, messenger.preferences.incomingSoundEnabled, !self.isQuietNow() {
                self.soundPlayer.play(id: messenger.preferences.incomingSoundID)
            }
            if kind == .visitStart, messenger.preferences.visitsEnabled {
                Task { @MainActor in
                    let reply = self.runtime.phrase(event: "messenger.visitAccept")
                        ?? (self.runtime.config.ui.locale == "en" ? "I'm here!" : "我來啦！")
                    do {
                        let result = try await messenger.send(
                            text: reply, to: contact.id, kind: .visitAccept,
                            presence: self.currentFishPresence()
                        )
                        if messenger.preferences.currentStatus != .doNotDisturb,
                           messenger.preferences.effectiveVisitShowsBubble {
                            self.panelController.showFriendMessage(
                                id: result.record.id, contactID: contact.id, text: reply,
                                color: messenger.preferences.bubbleColor,
                                speaker: .owner,
                                duration: messenger.preferences.effectiveMessageDisplaySeconds
                            )
                        }
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
            if messenger.preferences.currentStatus == .doNotDisturb, kind != .status { return }
            switch kind {
            case .text:
                let visiting = messenger.activeVisitContactID == contact.id
                if visiting, messenger.preferences.effectiveVisitShowsBubble {
                    self.panelController.showFriendMessage(
                        id: message.id, contactID: contact.id, text: message.text,
                        color: messenger.preferences.bubbleColor, speaker: .visitor,
                        duration: messenger.preferences.effectiveMessageDisplaySeconds
                    )
                } else if messenger.preferences.effectiveMessageShowsBubble {
                    self.panelController.say(
                        "\(message.senderName)：\(message.text)",
                        event: "messenger.received",
                        duration: messenger.preferences.effectiveMessageDisplaySeconds,
                        priority: SpeechPriority.messenger,
                        replaceKey: "messenger.\(message.id.uuidString)",
                        color: messenger.preferences.bubbleColor
                    )
                }
            case .visitStart, .visitAccept:
                if messenger.preferences.effectiveVisitShowsBubble {
                self.panelController.showFriendMessage(
                    id: message.id,
                    contactID: contact.id,
                    text: message.text,
                    color: messenger.preferences.bubbleColor,
                    speaker: .visitor,
                    duration: messenger.preferences.effectiveMessageDisplaySeconds
                )
                }
            case .visitEnd:
                self.panelController.say(
                    "\(message.senderName) 回家啦，下次再玩。",
                    event: "messenger.visitEnd",
                    duration: 5,
                    priority: SpeechPriority.messenger,
                    replaceKey: "messenger.\(message.id.uuidString)",
                    color: message.bubbleColor
                )
            case .status:
                break
            }
        }
        messenger.onError = { [weak self] error in
            guard let self else { return }
            if let serviceError = error as? FishMessengerServiceError {
                switch serviceError {
                case .rejectedUnknownSender, .rejectedInvalidEnvelope:
                    NSLog("Fish messenger rejected an unauthenticated relay record: %@", error.localizedDescription)
                    return
                case .persistenceFailed(let operation, _) where operation == "profile load":
                    NSLog("Fish identity is not available at launch: %@", error.localizedDescription)
                    return
                case .persistenceFailed:
                    self.panelController.say(
                        self.runtime.config.ui.locale == "en"
                            ? "I couldn't save the latest fish-message state."
                            : "刚才的鱼鱼消息状态没有保存好。",
                        event: "messenger.persistenceError",
                        duration: 5,
                        priority: SpeechPriority.urgent,
                        replaceKey: "messenger.persistenceError"
                    )
                    return
                case .visitsUnavailable, .profileCreationInProgress:
                    return
                }
            }
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
            snooze: { [weak self, weak clocks] id in
                do { try clocks?.snoozeAlert(id: id, minutes: 5) }
                catch { self?.reportClockPersistenceError(error) }
            },
            dismiss: { [weak self, weak clocks] id in
                do { try clocks?.dismissAlert(id: id) }
                catch { self?.reportClockPersistenceError(error) }
            }
        )
        clocks.workdays = runtime.config.schedule.workdays
        clocks.onTick = { [weak self] state, text in
            self?.panelController.updateClock(state: state, timerText: text)
            self?.updateClockMenu(state)
        }
        clocks.onEvent = { [weak self] event, state in self?.handleClockEvent(event, state: state) }
        clocks.onError = { [weak self] error in self?.reportClockPersistenceError(error) }
        clockService = clocks
        clocks.start()

        let routine = RoutineService(runtime: runtime)
        routine.onPhrase = { [weak self] event, context in
            DispatchQueue.main.async { self?.deliverPhrase(event: event, context: context) }
        }
        routine.onError = { error in
            NSLog("Routine state could not be persisted: %@", error.localizedDescription)
        }
        routineService = routine
        routine.start()

        let calendar = CalendarService(runtime: runtime)
        calendar.onPhrase = { [weak self] event, context in
            DispatchQueue.main.async { self?.deliverPhrase(event: event, context: context) }
        }
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

        let sendMessage = NSMenuItem(title: "魚魚傳話…", action: #selector(openFishMessageComposer), keyEquivalent: "")
        sendMessage.target = self
        menu.addItem(sendMessage)
        messengerSendMenuItem = sendMessage

        let messages = NSMenuItem(title: "聊天紀錄", action: #selector(openFishChat), keyEquivalent: "")
        messages.target = self
        menu.addItem(messages)
        messengerMenuItem = messages

        let fishStatus = NSMenuItem(title: "我的狀態", action: nil, keyEquivalent: "")
        let fishStatusMenu = NSMenu()
        for status in FishUserStatus.allCases {
            let option = NSMenuItem(
                title: status.title(isEnglish: runtime.config.ui.locale == "en"),
                action: #selector(selectFishStatus(_:)),
                keyEquivalent: ""
            )
            option.target = self
            option.representedObject = status.rawValue
            fishStatusMenu.addItem(option)
        }
        fishStatusMenu.addItem(.separator())
        let clearStatus = NSMenuItem(
            title: runtime.config.ui.locale == "en" ? "Clear Status" : "清除狀態",
            action: #selector(selectFishStatus(_:)),
            keyEquivalent: ""
        )
        clearStatus.target = self
        fishStatusMenu.addItem(clearStatus)
        fishStatus.submenu = fishStatusMenu
        menu.addItem(fishStatus)
        fishStatusMenuItem = fishStatus

        let chat = NSMenuItem(title: "和水滴魚聊天…", action: #selector(openDialogue), keyEquivalent: "")
        chat.target = self
        menu.addItem(chat)

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
        let title = runtime.config.ui.locale == "en" ? "Chat History" : "聊天紀錄"
        messengerMenuItem?.title = unreadCount > 0
            ? "\(title) · \(unreadCount > 99 ? "99+" : String(unreadCount))"
            : title
        messengerSendMenuItem?.title = runtime.config.ui.locale == "en" ? "Fish Message…" : "魚魚傳話…"
    }

    @MainActor private func visibleUnreadCount(_ messenger: FishMessengerService) -> Int {
        let preferences = messenger.preferences
        return messenger.records.filter { record in
            guard record.direction == .incoming, !record.isRead else { return false }
            switch record.kind {
            case .text:
                return preferences.effectiveMessageShowsMailbox
            case .visitStart, .visitAccept, .visitEnd:
                return preferences.effectiveVisitShowsMailbox
            case .status:
                return false
            }
        }.count
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
                  self.clockQuickController?.window?.isVisible != true,
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

    private func reportClockPersistenceError(_ error: Error) {
        NSLog("Clock state could not be persisted: %@", error.localizedDescription)
        panelController.say(
            runtime.config.ui.locale == "en"
                ? "I couldn't save that clock change. Please try again."
                : "闹钟状态没有保存好，请再试一次。",
            event: "clock.persistenceError",
            duration: 5,
            priority: SpeechPriority.urgent,
            replaceKey: "clock.persistenceError"
        )
    }

    @MainActor private func deliverPhrase(event: String, context: [String: JSONValue]) {
        if event.hasPrefix("schedule."), !runtime.config.language.categories.schedule { return }
        if event.hasPrefix("system."), !runtime.config.language.categories.system { return }
        if event.hasPrefix("calendar."), !runtime.config.language.categories.calendar { return }
        if event.hasPrefix("clock."), !runtime.config.language.categories.clock { return }
        let selectedEvent: String
        if event == "idle.chatter",
           let contactID = messengerService?.activeVisitContactID,
           lastActiveVisitContactID == contactID {
            guard visitIdleSpokenContactID != contactID else { return }
            selectedEvent = "messenger.visitIdle"
        } else {
            selectedEvent = event
        }
        guard let phrase = runtime.phrase(event: selectedEvent, context: context) else { return }
        if selectedEvent == "messenger.visitIdle" {
            visitIdleSpokenContactID = messengerService?.activeVisitContactID
        }
        let priority = selectedEvent.hasPrefix("calendar.") ? SpeechPriority.calendar
            : selectedEvent.hasPrefix("system.") ? SpeechPriority.urgent
            : SpeechPriority.schedule
        panelController.say(
            phrase,
            event: selectedEvent,
            duration: selectedEvent == "calendar.starting" ? 7 : 5.5,
            priority: priority,
            replaceKey: selectedEvent
        )
    }

    private func handleSustainedMemoryLimit() {
        guard previousSnapshot.activeCount == 0,
              settingsController?.window?.isVisible != true,
              clockQuickController?.window?.isVisible != true,
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
        let previous = runtime.config.startup.launchAtLogin
        let desired = !previous
        do {
            try LoginItemSettingTransaction.apply(
                previous: previous,
                desired: desired,
                updateSystem: { try LoginItemController.sync(enabled: $0) },
                saveConfiguration: { enabled in
                    try self.runtime.update { $0.startup.launchAtLogin = enabled }
                }
            )
            syncQuickSettingsMenu()
            settingsController?.mergeQuickSettingsFromRuntime()
        } catch {
            panelController.say("开机启动设置没有改成功。", event: "system.error", duration: 5.5, priority: SpeechPriority.urgent, replaceKey: "system.error")
        }
    }

    private func updateQuickSetting(event: String, change: (inout AppConfig) -> Void) {
        do {
            try runtime.update(change)
            panelController.apply(runtime: runtime)
            syncQuickSettingsMenu()
            settingsController?.mergeQuickSettingsFromRuntime()
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
        let status = messengerService?.preferences.currentStatus
        return FishPresence(
            characterPackID: runtime.config.pet.characterPackId,
            customization: runtime.config.pet.customization[runtime.config.pet.characterPackId],
            accessories: runtime.config.pet.accessories[runtime.config.pet.characterPackId],
            status: status,
            statusFaceID: status.map { messengerService?.preferences.faceID(for: $0) ?? $0.faceID },
            statusAccessoryID: status.flatMap { messengerService?.preferences.accessoryID(for: $0) },
            statusAccessories: status.flatMap { messengerService?.preferences.statusAccessorySpecs?[$0.rawValue] }
        )
    }

    @MainActor @objc private func selectFishStatus(_ sender: NSMenuItem) {
        let status = (sender.representedObject as? String).flatMap(FishUserStatus.init(rawValue:))
        guard let messengerService else { return }
        Task { @MainActor in
            do {
                let base = currentFishPresence()
                let presence = FishPresence(
                    characterPackID: base.characterPackID,
                    customization: base.customization,
                    accessories: base.accessories,
                    status: status,
                    statusFaceID: status.map { messengerService.preferences.faceID(for: $0) },
                    statusAccessoryID: status.flatMap { messengerService.preferences.accessoryID(for: $0) },
                    statusAccessories: status.flatMap { messengerService.preferences.statusAccessorySpecs?[$0.rawValue] }
                )
                try await messengerService.updateStatus(status, presence: presence)
                panelController.setStatusAppearance(
                    faceID: status.map { messengerService.preferences.faceID(for: $0) },
                    accessoryID: status.flatMap { messengerService.preferences.accessoryID(for: $0) },
                    accessories: status.flatMap { messengerService.preferences.statusAccessorySpecs?[$0.rawValue] },
                    customization: runtime.config.pet.customization[runtime.config.pet.characterPackId]
                )
            } catch {
                panelController.say(
                    runtime.config.ui.locale == "en" ? "Status could not be shared." : "狀態暫時沒能同步。",
                    event: "messenger.error", duration: 4,
                    priority: SpeechPriority.interaction, replaceKey: "messenger.status.error"
                )
            }
        }
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

    @MainActor @objc private func openClocks() {
        guard let clockService else { return }
        if clockQuickController == nil {
            clockQuickController = ClockQuickWindowController(
                service: clockService,
                locale: runtime.config.ui.locale
            )
        }
        clockQuickController?.updateLocale(runtime.config.ui.locale)
        clockQuickController?.showWindow(nil)
        clockQuickController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor @objc private func openFishChat() {
        openFishHistory()
    }

    @MainActor private func openFishHistory(contactID: UUID? = nil, preferUnread: Bool = false) {
        guard let messenger = messengerService else { return }
        if fishChatController == nil {
            fishChatController = FishChatWindowController(
                messengerService: messenger,
                locale: runtime.config.ui.locale,
                presenceProvider: { [weak self] in self?.currentFishPresence() },
                visitPhraseProvider: { [weak self] event, fallback in
                    self?.runtime.phrase(event: event) ?? fallback
                },
                onSent: { [weak self] result, contact in
                    self?.presentSentFishMessage(result, contact: contact)
                }
            )
            fishChatController?.onVisibilityChanged = { [weak self] visible in
                self?.panelController.setComposerPaused(visible)
            }
        }
        fishChatController?.showHistory(contactID: contactID, preferUnread: preferUnread)
        fishChatController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor @objc private func openFishMessageComposer() {
        presentFishMessageComposer(preferredContactID: messengerService?.activeVisitContactID)
    }

    @MainActor private func openFishMessageComposerForUnread() {
        let contactID = messengerService?.records
            .filter { $0.direction == .incoming && !$0.isRead }
            .max(by: { $0.sentAt < $1.sentAt })?.contactID
        presentFishMessageComposer(preferredContactID: contactID)
    }

    @MainActor private func presentFishMessageComposer(preferredContactID: UUID?) {
        guard let messenger = messengerService else { return }
        if fishMessageComposeController == nil {
            fishMessageComposeController = FishMessageComposeWindowController(
                messengerService: messenger,
                locale: runtime.config.ui.locale,
                presenceProvider: { [weak self] in self?.currentFishPresence() },
                onSent: { [weak self] result, contact in
                    self?.presentSentFishMessage(result, contact: contact)
                }
            )
            fishMessageComposeController?.onVisibilityChanged = { [weak self] visible in
                self?.panelController.setComposerPaused(visible)
            }
        }
        panelController.playClickReaction()
        fishMessageComposeController?.showComposer(
            preferredContactID: preferredContactID,
            sceneAnchor: panelController.sceneAnchor
        )
        fishMessageComposeController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor private func presentSentFishMessage(
        _ result: FishMessengerService.SendResult,
        contact: FishContact
    ) {
        guard let messenger = messengerService else { return }
        panelController.playEffect(.completed)
        let isVisitChat = messenger.activeVisitContactID == contact.id
        guard messenger.preferences.currentStatus != .doNotDisturb else { return }
        if isVisitChat {
            panelController.showFriendMessage(
                id: result.record.id, contactID: contact.id, text: result.record.text,
                color: result.record.bubbleColor ?? messenger.preferences.bubbleColor,
                speaker: .owner, duration: messenger.preferences.effectiveMessageDisplaySeconds
            )
        } else {
            let acknowledgement = runtime.phrase(event: "messenger.sent")
                ?? (runtime.config.ui.locale == "en" ? "Message delivered." : "傳話送到啦。")
            panelController.say(
                acknowledgement, event: "messenger.sent", duration: 2.8,
                priority: SpeechPriority.interaction, replaceKey: "messenger.sent"
            )
        }
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
                runtime: runtime, clockService: clockService, messengerService: messengerService
            ) { [weak self] in
                guard let self else { return }
                self.panelController.apply(runtime: self.runtime)
                self.taskMonitor?.includeTitles = self.runtime.config.privacy.includeTaskTitles
                self.taskMonitor?.enabledProviders = self.enabledProviders()
                self.clockService?.workdays = self.runtime.config.schedule.workdays
                self.syncQuickSettingsMenu()
                Task { @MainActor in
                    self.updateMessengerMenu(unreadCount: self.messengerService?.unreadCount ?? 0)
                    self.fishChatController?.updateLocale(self.runtime.config.ui.locale)
                    self.fishMessageComposeController?.updateLocale(self.runtime.config.ui.locale)
                    self.clockQuickController?.updateLocale(self.runtime.config.ui.locale)
                }
                self.performanceMonitor?.memoryLimitMB = self.runtime.config.performance.memoryLimitMb
                self.performanceMonitor?.autoQuitEnabled = self.runtime.config.performance.autoQuitEnabled
                if !self.runtime.config.performance.panelEnabled { self.panelController.updatePerformance(nil) }
                self.calendarService?.stop()
                self.calendarService?.start()
            }
        }
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
        settingsController?.window?.orderFrontRegardless()
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
