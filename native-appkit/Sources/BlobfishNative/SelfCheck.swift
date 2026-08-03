import AppKit
import Darwin
import Foundation

enum SelfCheck {
    static func run() -> Bool {
        let checks: [(String, () throws -> Bool)] = [
            ("private lease recovery", privateLeaseRecovery),
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
            ("native update channel isolation", nativeUpdateChannelIsolation),
            ("single instance lock", singleInstanceLock),
            ("dragged height preservation", draggedHeightPreservation),
            ("nearest display preserves pet height", nearestDisplayPreservesPetHeight),
            ("display-paced pet motion", displayPacedPetMotion),
            ("display-timed carousel easing", displayTimedCarouselEasing),
            ("pet reaction geometry", petReactionGeometry),
            ("task carousel geometry", taskCarouselGeometry),
            ("speech priority and mood restore", speechPriorityAndMoodRestore),
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
