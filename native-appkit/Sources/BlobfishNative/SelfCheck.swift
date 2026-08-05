import AppKit
import Darwin
import Foundation

enum SelfCheck {
    static func run() -> Bool {
        let checks: [(String, () throws -> Bool)] = [
            ("private lease recovery", privateLeaseRecovery),
            ("orphaned task leases expire promptly", orphanedTaskLeasesExpirePromptly),
            ("waiting fallback title", waitingFallbackTitle),
            ("terminal status expiry", terminalStatusExpiry),
            ("unsafe input rejection", unsafeInputRejection),
            ("shared config migration", sharedConfigMigration),
            ("config round trip", configRoundTrip),
            ("unsafe config rejection", unsafeConfigRejection),
            ("shared pack compatibility", sharedPackCompatibility),
            ("phrase rules and templates", phraseRulesAndTemplates),
            ("shared runtime recovery", sharedRuntimeRecovery),
            ("custom SVG and accessory rendering", customSVGAndAccessoryRendering),
            ("shared alarm and timer state", sharedAlarmAndTimerState),
            ("quick timer clock threshold", quickTimerClockThreshold),
            ("native update channel isolation", nativeUpdateChannelIsolation),
            ("single instance lock", singleInstanceLock),
            ("dragged height preservation", draggedHeightPreservation),
            ("nearest display preserves pet height", nearestDisplayPreservesPetHeight),
            ("visit formation joins movement bounds", visitFormationJoinsMovementBounds),
            ("scene layout coordinates satellites", sceneLayoutCoordinatesSatellites),
            ("friend messages stack and expire", friendMessagesStackAndExpire),
            ("display-paced pet motion", displayPacedPetMotion),
            ("hover and menu pause pet motion", hoverAndMenuPausePetMotion),
            ("display-timed carousel easing", displayTimedCarouselEasing),
            ("unclipped CSS-matched pet shadow", unclippedCSSMatchedPetShadow),
            ("native blush matches Electron CSS", nativeBlushMatchesElectronCSS),
            ("expressions stay below independent eyewear", expressionsStayBelowIndependentEyewear),
            ("expression anchors follow authored eye lines", expressionAnchorsFollowEyeLines),
            ("expression respects character viewBox origin", expressionRespectsCharacterViewBoxOrigin),
            ("non-face accessories respect character viewBox origin", nonFaceAccessoryRespectsCharacterViewBoxOrigin),
            ("performance percentages share system capacity", performancePercentagesShareSystemCapacity),
            ("system RAM excludes reclaimable cache", systemRAMExcludesReclaimableCache),
            ("performance panel stays on canvas", performancePanelStaysOnCanvas),
            ("performance bars nest and animate", performanceBarsNestAndAnimate),
            ("pet reaction geometry", petReactionGeometry),
            ("task carousel geometry", taskCarouselGeometry),
            ("continuous task spinner timeline", continuousTaskSpinnerTimeline),
            ("inactive preview releases without lazy weak crash", inactivePreviewReleasesWithoutLazyWeakCrash),
            ("early app termination tolerates incomplete launch", earlyAppTerminationToleratesIncompleteLaunch),
            ("speech priority and mood restore", speechPriorityAndMoodRestore),
            ("fish invite validation", fishInviteValidation),
            ("fish self invite is rejected", fishSelfInviteIsRejected),
            ("fish message end-to-end encryption", fishMessageEncryption),
            ("fish visit appearance stays encrypted", fishVisitEncryption),
            ("fish history preserves unread messages", fishHistoryPersistence),
            ("fish message duration migrates from old preferences", fishMessageDurationMigration),
        ]
        var passed = 0
        for (name, check) in checks {
            do {
                if try check() {
                    passed += 1
                    print("PASS \(name)")
                } else {
                    print("FAIL \(name)")
                }
            } catch {
                print("FAIL \(name): \(error)")
            }
        }
        print("Self-check: \(passed)/\(checks.count) passed")
        return passed == checks.count
    }

    private static func fishInviteValidation() throws -> Bool {
        let identity = FishMessengerIdentity()
        let invite = try FishInvite(
            relayURL: URL(string: "https://fish.example.com")!,
            inboxID: String(repeating: "i", count: 24),
            deliveryToken: String(repeating: "t", count: 48),
            publicKey: identity.publicKey,
            displayName: "小鱼"
        )
        guard try FishInvite.decode(invite.encoded()) == invite else { return false }
        do {
            _ = try FishInvite.decode("fish1_not-json")
            return false
        } catch {
            return true
        }
    }

    private static func fishSelfInviteIsRejected() throws -> Bool {
        let owner = FishMessengerIdentity()
        let friend = FishMessengerIdentity()
        let relayURL = URL(string: "https://fish.example.com")!
        let profile = FishMessengerProfile(
            relayURL: relayURL,
            inboxID: String(repeating: "i", count: 24),
            readToken: String(repeating: "r", count: 48),
            deliveryToken: String(repeating: "t", count: 48),
            privateKey: owner.rawPrivateKey.base64EncodedString(),
            displayName: "我的鱼",
            contacts: []
        )
        let ownInvite = try FishInvite(
            relayURL: relayURL,
            inboxID: String(repeating: "o", count: 24),
            deliveryToken: String(repeating: "d", count: 48),
            publicKey: owner.publicKey,
            displayName: "我的鱼"
        )
        do {
            try FishContactImportPolicy.validate(ownInvite, for: profile)
            return false
        } catch FishMessengerError.invalidInvite {
            // Expected: importing your own delivery capability must fail closed.
        }
        let friendInvite = try FishInvite(
            relayURL: relayURL,
            inboxID: String(repeating: "f", count: 24),
            deliveryToken: String(repeating: "p", count: 48),
            publicKey: friend.publicKey,
            displayName: "朋友的鱼"
        )
        try FishContactImportPolicy.validate(friendInvite, for: profile)
        return true
    }

    private static func fishMessageEncryption() throws -> Bool {
        let sender = FishMessengerIdentity()
        let recipient = FishMessengerIdentity()
        let message = try FishMessage(senderName: "Kinley", text: "  今晚记得吃饭。  ")
        let envelope = try sender.encrypt(message, for: recipient.publicKey)
        guard try recipient.decrypt(envelope, expectedSenderPublicKey: sender.publicKey).text == "今晚记得吃饭。" else {
            return false
        }
        let stranger = FishMessengerIdentity()
        do {
            _ = try stranger.decrypt(envelope, expectedSenderPublicKey: sender.publicKey)
            return false
        } catch {
            return true
        }
    }

    private static func fishVisitEncryption() throws -> Bool {
        let sender = FishMessengerIdentity()
        let recipient = FishMessengerIdentity()
        let presence = FishPresence(
            characterPackID: "blobfish",
            customization: .object(["body": .object(["width": .number(1.1)])]),
            accessories: .object(["equipped": .object(["hat": .string("hat-crown")])])
        )
        let message = try FishMessage(
            senderName: "小鱼", text: "来串门啦！", kind: .visitStart,
            bubbleColor: "#1F7AE8", presence: presence
        )
        let envelope = try sender.encrypt(message, for: recipient.publicKey)
        let decoded = try recipient.decrypt(envelope, expectedSenderPublicKey: sender.publicKey)
        return decoded.kind == .visitStart && decoded.presence == presence && decoded.bubbleColor == "#1F7AE8"
    }

    private static func fishHistoryPersistence() throws -> Bool {
        try withPrivateDirectory { directory in
            let store = FishFriendStore(directoryURL: directory)
            let record = FishMessageRecord(
                id: UUID(), contactID: UUID(), direction: .incoming, sentAt: Date(),
                senderName: "朋友", text: "别忘了看消息", kind: .text, isRead: false,
                bubbleColor: "#E65D83", presence: nil
            )
            try store.save(preferences: .defaults, records: [record])
            let loaded = store.load()
            return loaded.0 == .defaults && loaded.1 == [record] && loaded.1.first?.isRead == false
        }
    }

    private static func fishMessageDurationMigration() throws -> Bool {
        let oldJSON = Data("""
        {
            "bubbleColor":"#1F7AE8",
            "incomingSoundEnabled":true,
            "incomingSoundID":"Submarine",
            "visitsEnabled":true
        }
        """.utf8)
        let migrated = try JSONDecoder().decode(FishFriendPreferences.self, from: oldJSON)
        var configured = migrated
        configured.messageDisplaySeconds = 36
        let roundTrip = try JSONDecoder().decode(
            FishFriendPreferences.self,
            from: JSONEncoder().encode(configured)
        )
        configured.messageDisplaySeconds = -5
        return migrated.messageDisplaySeconds == nil
            && migrated.effectiveMessageDisplaySeconds == 20
            && roundTrip.effectiveMessageDisplaySeconds == 36
            && configured.effectiveMessageDisplaySeconds == 1
    }

    private static func hoverAndMenuPausePetMotion() -> Bool {
        !PetMovementPause.shouldPause(hovering: false, menuOpen: false, interacting: false, dragging: false)
            && PetMovementPause.shouldPause(hovering: true, menuOpen: false, interacting: false, dragging: false)
            && PetMovementPause.shouldPause(hovering: false, menuOpen: true, interacting: false, dragging: false)
            && PetMovementPause.shouldPause(hovering: false, menuOpen: false, interacting: true, dragging: false)
            && PetMovementPause.shouldPause(hovering: false, menuOpen: false, interacting: false, dragging: true)
    }

    private static func privateLeaseRecovery() throws -> Bool {
        try withPrivateDirectory { directory in
            let now = 50_000.0
            try writeLease([
                "version": 1,
                "provider": "codex",
                "event": "running",
                "sessionId": "session-1",
                "turnId": "turn-1",
                "title": "修复原生桌宠",
                "timestamp": now - 500,
                "startedAt": now - 5_000,
            ], named: String(repeating: "a", count: 64) + ".json", in: directory)
            let leases = try TaskLeaseReader(directoryURL: directory).read(nowMilliseconds: now)
            return leases.count == 1
                && leases[0].title == "修复原生桌宠"
                && TaskSnapshot.build(from: leases, nowMilliseconds: now) == TaskSnapshot(
                    state: .running,
                    title: "修复原生桌宠",
                    activeCount: 1,
                    tasks: [TaskCard(
                        id: "session-1", provider: "codex", state: .running,
                        title: "修复原生桌宠", timestamp: now - 500
                    )]
                )
        }
    }

    private static func orphanedTaskLeasesExpirePromptly() throws -> Bool {
        try withPrivateDirectory { directory in
            let now = 4 * 60 * 60 * 1_000.0
            try writeLease([
                "version": 1,
                "provider": "codex",
                "event": "started",
                "sessionId": "orphaned-start",
                "turnId": "turn-start",
                "timestamp": now - TaskLeaseReader.startedMaximumAgeMilliseconds - 1,
            ], named: String(repeating: "1", count: 64) + ".json", in: directory)
            try writeLease([
                "version": 1,
                "provider": "codex",
                "event": "running",
                "sessionId": "orphaned-running",
                "turnId": "turn-running",
                "timestamp": now - TaskLeaseReader.runningMaximumAgeMilliseconds - 1,
            ], named: String(repeating: "2", count: 64) + ".json", in: directory)
            try writeLease([
                "version": 1,
                "provider": "claude-code",
                "event": "needs_input",
                "sessionId": "still-waiting",
                "turnId": "turn-waiting",
                "timestamp": now - TaskLeaseReader.runningMaximumAgeMilliseconds - 1,
            ], named: String(repeating: "3", count: 64) + ".json", in: directory)
            let leases = try TaskLeaseReader(directoryURL: directory).read(nowMilliseconds: now)
            return leases.map(\.sessionId) == ["still-waiting"]
        }
    }

    private static func waitingFallbackTitle() throws -> Bool {
        try withPrivateDirectory { directory in
            let now = 80_000.0
            try writeLease([
                "version": 1,
                "provider": "claude-code",
                "event": "needs_input",
                "sessionId": "session-2",
                "timestamp": now - 100,
            ], named: String(repeating: "b", count: 64) + ".json", in: directory)
            let leases = try TaskLeaseReader(directoryURL: directory).read(nowMilliseconds: now)
            return TaskSnapshot.build(from: leases, nowMilliseconds: now) == TaskSnapshot(
                state: .waiting,
                title: "Claude Code 任务",
                activeCount: 1,
                tasks: [TaskCard(
                    id: "session-2", provider: "claude-code", state: .waiting,
                    title: "Claude Code 任务", timestamp: now - 100
                )]
            )
        }
    }

    private static func terminalStatusExpiry() throws -> Bool {
        let lease = TaskLease(
            version: 1,
            provider: "codex",
            event: .completed,
            sessionId: "session",
            turnId: nil,
            title: "完成测试",
            timestamp: 10_000,
            startedAt: nil
        )
        return TaskSnapshot.build(from: [lease], nowMilliseconds: 14_000).state == .completed
            && TaskSnapshot.build(from: [lease], nowMilliseconds: 16_000) == .idle
    }

    private static func unsafeInputRejection() throws -> Bool {
        try withPrivateDirectory { directory in
            let target = directory.appendingPathComponent("target.json")
            try Data("{}".utf8).write(to: target)
            let symlink = directory.appendingPathComponent(String(repeating: "c", count: 64) + ".json")
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)

            let oversized = directory.appendingPathComponent(String(repeating: "d", count: 64) + ".json")
            try Data(repeating: 1, count: TaskLeaseReader.maximumFileBytes + 1).write(to: oversized)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: oversized.path)
            guard try TaskLeaseReader(directoryURL: directory).read().isEmpty else { return false }

            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            do {
                _ = try TaskLeaseReader(directoryURL: directory).read()
                return false
            } catch TaskLeaseReaderError.insecureDirectory {
                return true
            }
        }
    }

    private static func sharedConfigMigration() throws -> Bool {
        try withPrivateDirectory { directory in
            let userConfig: [String: Any] = [
                "version": 1,
                "ui": ["locale": "en-US"],
                "schedule": [
                    "workdays": [5, 1, 1], "lunchTime": "12:30", "offWorkTime": "18:15",
                    "halfHourReminders": false, "lunchReminder": true, "offWorkReminder": true,
                ],
                "quietHours": ["enabled": false, "start": "22:00", "end": "08:00"],
                "language": [
                    "packId": "blobfish-en", "idleEnabled": true, "rareEnabled": false,
                    "idleMinMinutes": 5, "idleMaxMinutes": 10,
                    "categories": ["schedule": true, "system": true, "calendar": false, "agents": true],
                ],
                "pet": [
                    "characterPackId": "blobfish-wotou", "speed": 2, "scale": 1.1,
                    "roamWhenTasks": false, "roamWhenNoTasks": true, "moveAxis": "vertical",
                    "customization": ["blobfish-wotou": ["bodyShape": "bun", "bodyHue": 14]],
                    "accessories": [:],
                ],
                "integrations": ["calendar": false, "codex": true, "claudeCode": true],
                "privacy": ["includeTaskTitles": true, "includeCalendarTitles": false],
            ]
            let data = try JSONSerialization.data(withJSONObject: userConfig)
            let file = directory.appendingPathComponent("settings.json")
            try data.write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let result = NativeConfigStore(directoryURL: directory).load()
            return result.warning == nil
                && result.config.ui.locale == "zh-CN"
                && result.config.schedule.workdays == [1, 5]
                && result.config.language.categories.clock
                && result.config.performance.memoryLimitMb == 1024
                && result.config.performance.panelSide == "left"
                && result.config.performance.panelVerticalPosition == 0.5
                && result.config.performance.panelDistance == 6
                && result.config.pet.customization["blobfish-wotou"]?.objectValue?["bodyShape"]?.stringValue == "bun"
        }
    }

    private static func configRoundTrip() throws -> Bool {
        try withPrivateDirectory { directory in
            var config = AppConfig.defaults
            config.ui.locale = "en"
            config.pet.roamWhenTasks = false
            config.sound.taskComplete.soundId = "Pop"
            let store = NativeConfigStore(directoryURL: directory)
            try store.save(config)
            var info = stat()
            guard lstat(store.fileURL.path, &info) == 0, info.st_mode & 0o777 == 0o600 else { return false }
            return store.load().config == config
        }
    }

    private static func unsafeConfigRejection() throws -> Bool {
        try withPrivateDirectory { directory in
            let target = directory.appendingPathComponent("target.json")
            try Data("{}".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(
                at: directory.appendingPathComponent("settings.json"),
                withDestinationURL: target
            )
            let result = NativeConfigStore(directoryURL: directory).load()
            return result.config == .defaults && result.warning != nil
        }
    }

    private static func sharedPackCompatibility() throws -> Bool {
        let catalog = try PackCatalog()
        let characters = try catalog.characters()
        let languages = try catalog.languages()
        let blobfish = try catalog.character(id: "blobfish")
        let chinese = try catalog.language(id: "blobfish-zh-TW")
        let dialogue = try catalog.dialogue(id: "blobfish-zh-TW")
        return characters.count >= 3
            && languages.count >= 4
            && FileManager.default.fileExists(atPath: blobfish.artURL.path)
            && NSImage(contentsOf: blobfish.artURL) != nil
            && chinese.phrases.contains(where: { $0.event == "agent.completed" })
            && chinese.phrases.contains(where: { $0.event == "system.battery" })
            && dialogue.nodes["games"]?.options.contains(where: { $0.game == "rps" }) == true
    }

    private static func phraseRulesAndTemplates() throws -> Bool {
        let phrases = [
            Phrase(
                id: "one", event: "agent.completed", text: "还有 {remaining} 个。", weight: 1,
                rarity: nil, cooldownMs: nil, conditions: ["remainingMin": .number(1)]
            ),
            Phrase(
                id: "two", event: "agent.completed", text: "都好了。", weight: 1,
                rarity: nil, cooldownMs: nil, conditions: ["remainingEquals": .number(0)]
            ),
        ]
        let engine = PhraseEngine(phrases: phrases, random: { 0 })
        return engine.select(event: "agent.completed", context: ["remaining": .number(2)])?.text == "还有 2 个。"
            && engine.select(event: "agent.completed", context: ["remaining": .number(0)])?.text == "都好了。"
    }

    private static func sharedRuntimeRecovery() throws -> Bool {
        try withPrivateDirectory { directory in
            let runtime = AppRuntime(applicationSupportURL: directory, packsRoot: ResourceLocator.packsRoot())
            try runtime.update {
                $0.pet.characterPackId = "grass-buddy"
                $0.language.packId = "grass-buddy-zh-CN"
            }
            return runtime.character?.id == "grass-buddy"
                && runtime.language?.id == "grass-buddy-zh-CN"
                && runtime.phrase(event: "agent.started") != nil
        }
    }

    private static func customSVGAndAccessoryRendering() throws -> Bool {
        let catalog = try PackCatalog()
        let pack = try catalog.character(id: "blobfish")
        let customization: JSONValue = .object([
            "body": .object(["width": .number(1.2), "height": .number(0.9), "shape": .string("wotou")]),
            "eyes": .object(["size": .number(1.1), "spacing": .number(2)]),
        ])
        let image = SVGAppearanceRenderer.image(character: pack, customization: customization, blinking: true)
        let restingData = SVGAppearanceRenderer.renderedSVGData(
            character: pack, customization: customization, blinking: false
        )
        let coveredData = SVGAppearanceRenderer.renderedSVGData(
            character: pack, customization: customization, blinking: false, hidesBaseEyes: true
        )
        let restingSVG = restingData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let coveredSVG = coveredData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let accessories = try catalog.accessories()
        let hasClock = accessories.contains(where: { $0.id == "alarm-clock" && $0.manifest.slot == "clock" })
        let restingFaceIsNeutral = !restingSVG.contains("tear") && restingSVG.contains("eye-left")
        let selectedFaceCoversEyes = !coveredSVG.contains("eye-left") && !coveredSVG.contains("tear")
        if image == nil || accessories.count < 80 || !hasClock || !restingFaceIsNeutral || !selectedFaceCoversEyes {
            print("  renderer=\(image != nil), accessories=\(accessories.count), clock=\(hasClock), neutral=\(restingFaceIsNeutral), covered=\(selectedFaceCoversEyes)")
            return false
        }
        return true
    }

    private static func sharedAlarmAndTimerState() throws -> Bool {
        try withPrivateDirectory { directory in
            let service = ClockService(directoryURL: directory)
            try service.createAlarm(label: "起床", mode: "daily", time: "09:30", date: nil, weekdays: [])
            try service.startTimer(minutes: 2, label: "测试")
            try service.pauseTimer()
            guard service.state.timer?.state == "paused", service.remainingTimerText() != nil else { return false }
            try service.resumeTimer()
            var preferences = service.state.preferences
            preferences.alarmSound.soundId = "Bottle"
            try service.updatePreferences(preferences)
            let reloaded = ClockService(directoryURL: directory)
            let file = directory.appendingPathComponent("clock-state.json")
            var info = stat()
            guard reloaded.state.alarms.first?.time == "09:30"
                && reloaded.state.timer?.state == "running"
                && reloaded.state.preferences.alarmSound.soundId == "Bottle"
                && lstat(file.path, &info) == 0
                && info.st_mode & 0o777 == 0o600 else { return false }
            var fixture = reloaded.state
            fixture.alerts = [.init(
                id: "alert:test", sourceType: "alarm", sourceId: "alarm:test", label: "测试",
                originalDueAtMs: 1, dueAtMs: 1, state: "ringing", ringStartedAtMs: 1
            )]
            var fixtureData = try JSONEncoder().encode(fixture)
            fixtureData.append(0x0A)
            try fixtureData.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let alerts = ClockService(directoryURL: directory)
            try alerts.snoozeAlert(id: "alert:test", minutes: 5)
            guard alerts.state.alerts.first?.state == "snoozed",
                  (alerts.state.alerts.first?.dueAtMs ?? 0) > Date().timeIntervalSince1970 * 1_000 else { return false }
            try alerts.dismissAlert(id: "alert:test")
            return alerts.state.alerts.isEmpty
        }
    }

    private static func visitFormationJoinsMovementBounds() -> Bool {
        let primary = NSRect(x: 110, y: 10, width: 100, height: 95)
        let companionFrame = NSRect(x: 168, y: 0, width: 170, height: 165)
        let companion = NSRect(x: 48, y: 10, width: 82, height: 79)
        let result = PetFormationGeometry.movementBounds(
            primaryBounds: primary,
            companionFrame: companionFrame,
            companionBounds: companion
        )
        return result == NSRect(x: 110, y: 10, width: 188, height: 95)
            && PetFormationGeometry.movementBounds(
                primaryBounds: primary,
                companionFrame: nil,
                companionBounds: nil
            ) == primary
    }

    private static func sceneLayoutCoordinatesSatellites() -> Bool {
        let canvas = NSRect(x: 0, y: 0, width: 340, height: 300)
        let character = NSRect(x: 117.5, y: 10, width: 105, height: 90)
        let panelSize = NSSize(width: 58, height: 90)
        let left = PetSceneLayoutCoordinator.performancePanelRect(
            in: canvas,
            characterBounds: character,
            companionBounds: nil,
            size: panelSize,
            preferredSide: "left",
            verticalPosition: 0.5,
            distance: 6
        )
        let companion = NSRect(x: 45, y: 10, width: 65, height: 80)
        let avoidingCompanion = PetSceneLayoutCoordinator.performancePanelRect(
            in: canvas,
            characterBounds: character,
            companionBounds: companion,
            size: panelSize,
            preferredSide: "left",
            verticalPosition: 0.5,
            distance: 6
        )
        let bubbles = PetSceneLayoutCoordinator.stackedBubbleRects(
            sizesOldestFirst: [NSSize(width: 120, height: 30), NSSize(width: 130, height: 34)],
            anchor: character,
            in: canvas,
            avoiding: []
        )
        return abs(character.minX - left.maxX - PetSceneLayoutCoordinator.satelliteGap) < 0.001
            && avoidingCompanion.minX > character.maxX
            && bubbles.count == 2
            && bubbles[0].minY > bubbles[1].maxY
            && bubbles.allSatisfy { canvas.insetBy(dx: 8, dy: 8).contains($0) }
    }

    private static func friendMessagesStackAndExpire() -> Bool {
        let now = Date(timeIntervalSince1970: 1_000)
        var stack: [PetMessageBubble] = []
        for index in 0..<4 {
            stack = PetMessageBubbleStack.inserting(
                PetMessageBubble(
                    id: UUID(),
                    text: "message-\(index)",
                    color: nil,
                    speaker: index.isMultiple(of: 2) ? .owner : .visitor,
                    expiresAt: now.addingTimeInterval(TimeInterval(index + 1))
                ),
                into: stack,
                now: now
            )
        }
        let afterTwoSeconds = PetMessageBubbleStack.active(
            stack,
            now: now.addingTimeInterval(2.5)
        )
        return stack.map(\.text) == ["message-1", "message-2", "message-3"]
            && afterTwoSeconds.map(\.text) == ["message-2", "message-3"]
            && PetMessageBubbleStack.opacity(distanceFromNewest: 0) == 1
            && PetMessageBubbleStack.opacity(distanceFromNewest: 1) == 0.68
            && PetMessageBubbleStack.opacity(distanceFromNewest: 2) == 0.38
    }

    private static func quickTimerClockThreshold() -> Bool {
        let now = 1_000_000.0
        func state(source: String?, remainingMs: Double, timerState: String = "running") -> ClockState {
            ClockState(
                version: 1,
                preferences: .init(
                    alarmSound: .init(enabled: true, soundId: "Ping"),
                    timerSound: .init(enabled: true, soundId: "Glass"),
                    allowSoundDuringQuietHours: true,
                    defaultSnoozeMinutes: 5
                ),
                alarms: [],
                timer: .init(
                    id: "timer:test", label: "", durationMs: remainingMs, state: timerState,
                    createdAtMs: 0,
                    dueAtMs: timerState == "running" ? now + remainingMs : nil,
                    remainingMs: timerState == "paused" ? remainingMs : nil,
                    source: source
                ),
                alerts: [],
                lastReconciledAtMs: 0
            )
        }

        return !ClockAccessoryPolicy.shouldShowClock(
            state: state(source: ClockTimerSource.quick, remainingMs: 900_001),
            nowMs: now
        )
            && ClockAccessoryPolicy.shouldShowClock(
                state: state(source: ClockTimerSource.quick, remainingMs: 900_000),
                nowMs: now
            )
            && ClockAccessoryPolicy.shouldShowClock(
                state: state(source: ClockTimerSource.quick, remainingMs: 600_000, timerState: "paused"),
                nowMs: now
            )
            && !ClockAccessoryPolicy.shouldShowClock(
                state: state(source: ClockTimerSource.settings, remainingMs: 60_000),
                nowMs: now
            )
            && !ClockAccessoryPolicy.shouldShowClock(
                state: state(source: nil, remainingMs: 60_000),
                nowMs: now
            )
    }

    private static func nativeUpdateChannelIsolation() throws -> Bool {
        let asset = NativeUpdateManifest.Asset(
            name: "BlobfishNative-0.2.0-macOS-arm64.zip", size: 1024,
            digest: "sha256:" + String(repeating: "a", count: 64),
            url: "https://github.com/Kinley1212/blobfish-desktop-pet/releases/download/v0.2.0/BlobfishNative-0.2.0-macOS-arm64.zip"
        )
        let manifest = NativeUpdateManifest(
            channel: "native-appkit", version: "0.2.0", repository: NativeUpdater.repository,
            assets: ["arm64": asset]
        )
        guard try NativeUpdater.select(manifest: manifest, currentVersion: "0.1.0", architecture: "arm64") == .available(manifest, asset),
              try NativeUpdater.select(manifest: manifest, currentVersion: "0.2.0", architecture: "arm64") == .upToDate("0.2.0") else { return false }
        let electronManifest = NativeUpdateManifest(
            channel: "electron", version: "1.4.5", repository: NativeUpdater.repository,
            assets: ["arm64": asset]
        )
        do {
            _ = try NativeUpdater.select(manifest: electronManifest, currentVersion: "0.1.0", architecture: "arm64")
            return false
        } catch UpdaterError.invalidManifest { return true }
    }

    private static func singleInstanceLock() throws -> Bool {
        try withPrivateDirectory { directory in
            var first: SingleInstanceGuard? = SingleInstanceGuard()
            let second = SingleInstanceGuard()
            guard first?.acquire(in: directory) == true, second.acquire(in: directory) == false else { return false }
            first = nil
            let third = SingleInstanceGuard()
            return third.acquire(in: directory)
        }
    }

    private static func draggedHeightPreservation() throws -> Bool {
        let screen = NSRect(x: 0, y: 23, width: 1_440, height: 877)
        let visual = NSRect(x: 98, y: 4, width: 104, height: 95)
        guard let allowed = PetMovementGeometry.allowedOrigins(visibleFrame: screen, visualBounds: visual) else { return false }
        let dragged = PetMovementGeometry.clamped(NSPoint(x: 420, y: 350), to: allowed)
        let below = PetMovementGeometry.clamped(NSPoint(x: 420, y: -100), to: allowed)
        let above = PetMovementGeometry.clamped(NSPoint(x: 420, y: 1_000), to: allowed)
        return dragged.y == 350
            && below.y == allowed.minY
            && above.y == allowed.maxY
    }

    private static func nearestDisplayPreservesPetHeight() throws -> Bool {
        let visual = NSRect(x: 110, y: 4, width: 105, height: 95)
        let primary = NSRect(x: 0, y: 23, width: 1_440, height: 877)
        let secondary = NSRect(x: 1_440, y: 180, width: 1_920, height: 1_080)
        let onSecondary = NSPoint(x: 1_520, y: 640)
        guard let selected = PetMovementGeometry.allowedOrigins(
            visibleFrames: [primary, secondary],
            visualBounds: visual,
            currentOrigin: onSecondary
        ), let expected = PetMovementGeometry.allowedOrigins(
            visibleFrame: secondary,
            visualBounds: visual
        ) else { return false }

        let inDisplayGap = NSPoint(x: 1_350, y: 980)
        guard let nearest = PetMovementGeometry.allowedOrigins(
            visibleFrames: [primary, secondary],
            visualBounds: visual,
            currentOrigin: inDisplayGap
        ) else { return false }
        let projected = PetMovementGeometry.clamped(inDisplayGap, to: nearest)
        return selected == expected && projected.y > primary.minY + 100
    }

    private static func displayPacedPetMotion() -> Bool {
        let frameDistance = PetMotionTiming.travelDistance(speed: 1.5, elapsed: 1.0 / 60.0)
        let oneSecondDistance = frameDistance * 60
        let grassIdle = PetMotionTiming.swimOffset(elapsed: 1.8, characterID: "grass-buddy", state: .idle)
        let grassRoam = PetMotionTiming.swimOffset(elapsed: 0.42, characterID: "grass-buddy", state: .roam)
        return PetMotionTiming.framesPerSecond == 60
            && abs(oneSecondDistance - 50) < 0.001
            && abs(PetMotionTiming.swimOffset(elapsed: 0)) < 0.001
            && abs(PetMotionTiming.swimOffset(elapsed: 0.45) - 5) < 0.001
            && abs(PetMotionTiming.swimOffset(elapsed: 0.9)) < 0.001
            && abs(grassIdle - 2) < 0.001
            && abs(grassRoam - 4) < 0.001
    }

    private static func displayTimedCarouselEasing() -> Bool {
        let start = TaskCarouselGeometry.transitionProgress(0)
        let early = TaskCarouselGeometry.transitionProgress(0.25)
        let middle = TaskCarouselGeometry.transitionProgress(0.5)
        let end = TaskCarouselGeometry.transitionProgress(1)
        return start == 0
            && early > 0.5
            && middle > early
            && middle < 1
            && end == 1
    }

    private static func continuousTaskSpinnerTimeline() -> Bool {
        let started = TaskSpinnerTimeline.start(current: nil, hasRunningTask: true, now: 10)
        let preserved = TaskSpinnerTimeline.start(current: started, hasRunningTask: true, now: 11)
        let stopped = TaskSpinnerTimeline.start(current: preserved, hasRunningTask: false, now: 12)
        guard started == 10, preserved == 10, stopped == nil else { return false }
        return abs(TaskSpinnerTimeline.angle(start: 10, now: 10) - 90) < 0.001
            && abs(TaskSpinnerTimeline.angle(start: 10, now: 10.2)) < 0.001
            && abs(TaskSpinnerTimeline.angle(start: 10, now: 10.8) - 90) < 0.001
    }

    private static func unclippedCSSMatchedPetShadow() -> Bool {
        let requiredBottomSpace = abs(PetShadowStyle.offsetY) + PetShadowStyle.blurRadius
        return PetShadowStyle.offsetY == -3
            && PetShadowStyle.blurRadius == 3
            && PetShadowStyle.opacity == 0.15
            && PetShadowStyle.bottomInset >= requiredBottomSpace
    }

    private static func nativeBlushMatchesElectronCSS() -> Bool {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        guard let normal = PetBlushGeometry.style(level: 1, characterID: "blobfish", in: bounds),
              let deepWotou = PetBlushGeometry.style(level: 2, characterID: "blobfish-wotou", in: bounds) else {
            return false
        }
        func rectsMatch(_ actual: [CGRect], _ expected: [CGRect]) -> Bool {
            actual.count == expected.count && zip(actual, expected).allSatisfy { actual, expected in
                abs(actual.minX - expected.minX) < 0.0001
                    && abs(actual.minY - expected.minY) < 0.0001
                    && abs(actual.width - expected.width) < 0.0001
                    && abs(actual.height - expected.height) < 0.0001
            }
        }
        return rectsMatch(normal.cheekRects, [
            CGRect(x: 12, y: 42, width: 18, height: 12),
            CGRect(x: 70, y: 42, width: 18, height: 12),
        ])
            && abs(normal.green - 122 / 255) < 0.0001
            && abs(normal.blue - 146 / 255) < 0.0001
            && normal.centerAlpha == 0.78
            && rectsMatch(deepWotou.cheekRects, [
                CGRect(x: 18, y: 32, width: 22, height: 14),
                CGRect(x: 60, y: 32, width: 22, height: 14),
            ])
            && abs(deepWotou.green - 96 / 255) < 0.0001
            && abs(deepWotou.blue - 126 / 255) < 0.0001
            && deepWotou.centerAlpha == 0.92
            && PetBlushGeometry.style(level: 0, characterID: "blobfish", in: bounds) == nil
    }

    private static func expressionsStayBelowIndependentEyewear() -> Bool {
        let order = AccessoryLayerOrder.orderedIDs(
            equipped: [
                "hand": "bubble-tea",
                "eyewear": "round-glasses",
                "face": "face-happy",
                "hat": "bamboo-copter",
            ],
            systemAccessoryIDs: ["alarm-clock"]
        )
        let eyewearTuning = CharacterAccessories(.object([
            "equipped": .object(["face": .string("face-happy"), "eyewear": .string("round-glasses")]),
            "tuning": .object(["round-glasses": .object(["offsetX": .number(12)])]),
        ]))
        return order == ["face-happy", "bamboo-copter", "round-glasses", "bubble-tea", "alarm-clock"]
            && eyewearTuning.tuning["round-glasses"]?.offsetX == 12
            && eyewearTuning.tuning["face-happy"] == nil
    }

    private static func expressionAnchorsFollowEyeLines() throws -> Bool {
        let expected: [String: Double] = [
            "face-angry": 55, "face-annoyed": 56, "face-blank": 51, "face-cold": 46,
            "face-coy": 50, "face-cry": 50, "face-determined": 56, "face-dizzy": 50,
            "face-doubt": 52, "face-happy": 50, "face-hungry": 48, "face-love": 49,
            "face-money": 51, "face-nosebleed": 50, "face-panic": 55, "face-pitiful": 54,
            "face-proud": 46, "face-question": 53, "face-relieved": 54, "face-satisfied": 55,
            "face-scared": 57, "face-shocked": 53, "face-shy": 49, "face-side-eye": 52,
            "face-sleepy": 53, "face-smug": 58, "face-sparkle": 53, "face-star-eye": 52,
            "face-swirl-cheek": 53, "face-teasing": 49, "face-wink": 50,
        ]
        let faces = try PackCatalog().accessories().filter { $0.manifest.slot == "face" }
        guard faces.count == expected.count else { return false }
        return faces.allSatisfy { face in
            face.manifest.anchor.x == 50 && face.manifest.anchor.y == expected[face.id]
        }
    }

    private static func expressionRespectsCharacterViewBoxOrigin() throws -> Bool {
        let character = try PackCatalog().character(id: "blobfish-wotou")
        guard let canvas = SVGAppearanceRenderer.viewBox(for: character),
              let face = character.manifest.accessories?.slots["face"] else { return false }
        let target = CGRect(x: 10, y: 20, width: 129, height: 90)
        let point = ExpressionCanvasGeometry.targetAnchor(
            slotX: face.x,
            slotY: face.y,
            canvas: canvas,
            target: target
        )
        return canvas == CGRect(x: -16, y: 0, width: 172, height: 120)
            && abs(point.x - target.midX) < 0.001
            && abs(point.y - 65.75) < 0.001
    }

    // Regression guard for a bug where hat/eyewear/hand accessories were
    // placed with a call site that skipped the viewBox-origin subtraction
    // that the face slot already applied, leaving every non-face accessory
    // on the wotou fish (viewBox minX = -16) visibly offset from the body.
    // The "hand" slot's anchor (134, 86) isn't the canvas midpoint, so unlike
    // the face check above this one fails clearly if that subtraction is
    // ever dropped again.
    private static func nonFaceAccessoryRespectsCharacterViewBoxOrigin() throws -> Bool {
        let character = try PackCatalog().character(id: "blobfish-wotou")
        guard let canvas = SVGAppearanceRenderer.viewBox(for: character),
              let hand = character.manifest.accessories?.slots["hand"] else { return false }
        let target = CGRect(x: 10, y: 20, width: 129, height: 90)
        let point = ExpressionCanvasGeometry.targetAnchor(
            slotX: hand.x,
            slotY: hand.y,
            canvas: canvas,
            target: target
        )
        return canvas == CGRect(x: -16, y: 0, width: 172, height: 120)
            && abs(point.x - 122.5) < 0.001
            && abs(point.y - 45.5) < 0.001
    }

    private static func performancePercentagesShareSystemCapacity() -> Bool {
        let cpu = PerformanceMath.processCPUPercent(
            cpuTimeDelta: 0.68,
            elapsed: 2,
            logicalProcessorCount: 8
        )
        let ram = PerformanceMath.appRAMPercent(
            appMemoryMB: 256,
            physicalMemory: 16 * 1_024 * 1_024 * 1_024
        )
        return abs(cpu - 4.25) < 0.001 && abs(ram - 1.5625) < 0.001
    }

    private static func systemRAMExcludesReclaimableCache() -> Bool {
        abs(PerformanceMath.systemRAMPercent(
            activePages: 400,
            inactivePages: 300,
            wiredPages: 100,
            compressedPages: 100,
            fileBackedPages: 200,
            purgeablePages: 50,
            pageSize: 1,
            physicalMemory: 1_000
        ) - 65) < 0.001
    }

    private static func performancePanelStaysOnCanvas() -> Bool {
        let canvas = CGRect(x: 0, y: 0, width: 340, height: 300)
        let character = CGRect(x: 105.5, y: 10, width: 129, height: 90)
        let lowerLeft = PerformancePanelGeometry.rect(
            in: canvas, characterBounds: character, side: "left", verticalPosition: 0, distance: 6
        )
        let upperRight = PerformancePanelGeometry.rect(
            in: canvas, characterBounds: character, side: "right", verticalPosition: 1, distance: 6
        )
        let clamped = PerformancePanelGeometry.rect(
            in: canvas, characterBounds: character, side: "left", verticalPosition: 5, distance: 6
        )
        let nearby = PerformancePanelGeometry.rect(
            in: canvas, characterBounds: character, side: "left", verticalPosition: 0.5, distance: 2
        )
        let distant = PerformancePanelGeometry.rect(
            in: canvas, characterBounds: character, side: "left", verticalPosition: 0.5, distance: 28
        )
        let small = PerformancePanelGeometry.size(for: CGRect(x: 0, y: 0, width: 84, height: 58.5))
        let large = PerformancePanelGeometry.size(for: CGRect(x: 0, y: 0, width: 193.5, height: 135))
        let safeCanvas = canvas.insetBy(dx: PerformancePanelGeometry.margin, dy: PerformancePanelGeometry.margin)
        func containsInclusively(_ outer: CGRect, _ inner: CGRect) -> Bool {
            inner.minX >= outer.minX && inner.maxX <= outer.maxX
                && inner.minY >= outer.minY && inner.maxY <= outer.maxY
        }
        let valid = abs(character.minX - lowerLeft.maxX - PetSceneLayoutCoordinator.satelliteGap) < 0.001
            && abs(lowerLeft.minY - 8) < 0.001
            && abs(lowerLeft.width - 57.6) < 0.001
            && abs(lowerLeft.height - character.height) < 0.001
            && abs(upperRight.minX - character.maxX - PetSceneLayoutCoordinator.satelliteGap) < 0.001
            && upperRight.minY > lowerLeft.minY
            && abs(clamped.minX - lowerLeft.minX) < 0.001
            && abs(clamped.minY - upperRight.minY) < 0.001
            && abs(character.minX - nearby.maxX - 2) < 0.001
            && abs(character.minX - distant.maxX - 28) < 0.001
            && abs(small.width - 46) < 0.001
            && abs(small.height - 58.5) < 0.001
            && abs(large.width - 86.4) < 0.001
            && abs(large.height - 135) < 0.001
            && containsInclusively(safeCanvas, lowerLeft)
            && containsInclusively(safeCanvas, upperRight)
        if !valid {
            print("  lower=\(lowerLeft), upper=\(upperRight), clamped=\(clamped), safe=\(safeCanvas)")
        }
        return valid
    }

    private static func performanceBarsNestAndAnimate() -> Bool {
        let nested = PerformancePanelAnimation.nested(total: 18, app: 34)
        let start = PerformancePanelAnimation.progress(elapsed: 0, delay: 0)
        let delayed = PerformancePanelAnimation.progress(elapsed: 0.05, delay: 0.08)
        let middle = PerformancePanelAnimation.progress(elapsed: 0.30, delay: 0)
        let end = PerformancePanelAnimation.progress(elapsed: PerformancePanelAnimation.duration, delay: 0.16)
        return nested.total == 34
            && nested.app == 34
            && start == 0
            && delayed == 0
            && middle > 0 && middle < 1
            && end == 1
            && PerformancePanelAnimation.interpolate(10, 30, progress: 0.5) == 20
    }

    private static func petReactionGeometry() -> Bool {
        let pressed = PetEffectGeometry.transform(for: .hit, progress: 0.20)
        let rebound = PetEffectGeometry.transform(for: .hit, progress: 0.50)
        let bump = PetEffectGeometry.transform(for: .bump, progress: 0.30)
        let finished = PetEffectGeometry.transform(for: .hit, progress: 1)
        let grassHit = PetEffectGeometry.transform(for: .hit, progress: 0.22, characterID: "grass-buddy")
        let grassBump = PetEffectGeometry.transform(for: .bump, progress: 0.28, characterID: "grass-buddy")
        return pressed == PetEffectTransform(scaleX: 1.30, scaleY: 0.65, offsetX: 0, offsetY: -10)
            && rebound == PetEffectTransform(scaleX: 0.85, scaleY: 1.15, offsetX: 0, offsetY: 6)
            && bump == PetEffectTransform(scaleX: 1.38, scaleY: 0.60, offsetX: 0, offsetY: 0)
            && finished == PetEffectTransform(scaleX: 1, scaleY: 1, offsetX: 0, offsetY: 0)
            && grassHit == PetEffectTransform(scaleX: 1.18, scaleY: 0.78, offsetX: 0, offsetY: -7)
            && grassBump == PetEffectTransform(scaleX: 1.24, scaleY: 0.72, offsetX: 0, offsetY: 0)
    }

    private static func taskCarouselGeometry() -> Bool {
        let sixCards = TaskCarouselGeometry.visibleIndices(total: 6, frontIndex: 4)
        let twoCards = TaskCarouselGeometry.visibleIndices(total: 2, frontIndex: 1)
        let midpoint = TaskCarouselGeometry.interpolated(
            from: TaskCarouselGeometry.placements[0],
            to: TaskCarouselGeometry.placements[1],
            progress: 0.5
        )
        return sixCards.map(\.index) == [4, 5, 0, 1]
            && sixCards.map(\.placement.depth) == [0, 1, 2, 3]
            && sixCards[1].placement.horizontalOffset == 16
            && sixCards[3].placement.opacity == 0.40
            && twoCards.map(\.index) == [1, 0]
            && midpoint.horizontalOffset == 8
            && midpoint.downwardOffset == 5
            && abs(midpoint.opacity - 0.91) < 0.0001
            && TaskCarouselGeometry.visibleIndices(total: 0, frontIndex: 0).isEmpty
    }

    private static func inactivePreviewReleasesWithoutLazyWeakCrash() -> Bool {
        weak var releasedView: PetView?
        autoreleasepool {
            let view = PetView(frame: NSRect(x: 0, y: 0, width: 300, height: 190))
            releasedView = view
        }
        return releasedView == nil
    }

    private static func earlyAppTerminationToleratesIncompleteLaunch() -> Bool {
        let delegate = AppDelegate()
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )
        return true
    }

    private static func speechPriorityAndMoodRestore() -> Bool {
        var delivered: [String] = []
        var idleCount = 0
        let queue = SpeechQueue(
            deliver: { delivered.append($0.text) },
            onIdle: { idleCount += 1 }
        )
        queue.enqueue(text: "idle", event: "idle.chatter", faceID: nil, priority: 10, duration: 60, replaceKey: "idle")
        queue.enqueue(text: "agent", event: "agent.started", faceID: nil, priority: 60, duration: 60, replaceKey: "agent")
        queue.enqueue(text: "click", event: "interaction.click", faceID: nil, priority: 30, duration: 60, replaceKey: "click")
        queue.enqueue(text: "schedule", event: "schedule.offWork", faceID: nil, priority: 40, duration: 60, replaceKey: "schedule")
        queue.enqueue(text: "agent-new", event: "agent.completed", faceID: nil, priority: 60, duration: 60, replaceKey: "agent")
        guard delivered == ["idle", "agent", "agent-new"],
              queue.pending.map(\.text) == ["schedule", "click"] else {
            queue.clear()
            return false
        }
        queue.finishCurrent()
        let completedFace = ExpressionMoodSelector.pick(
            event: "agent.completed",
            available: ["face-happy"],
            random: { 0 }
        )
        let missingFace = ExpressionMoodSelector.pick(
            event: "agent.completed",
            available: [],
            random: { 0 }
        )
        queue.clear()
        return delivered == ["idle", "agent", "agent-new", "schedule"]
            && idleCount == 1
            && completedFace == "face-happy"
            && missingFace == nil
    }

    private static func withPrivateDirectory(_ body: (URL) throws -> Bool) throws -> Bool {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blobfish-native-checks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        return try body(root)
    }

    private static func writeLease(_ object: [String: Any], named name: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(name)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
