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
            ("quick settings merge preserves unrelated draft", quickSettingsMergePreservesUnrelatedDraft),
            ("unsafe config rejection", unsafeConfigRejection),
            ("shared pack compatibility", sharedPackCompatibility),
            ("phrase rules and templates", phraseRulesAndTemplates),
            ("shared runtime recovery", sharedRuntimeRecovery),
            ("custom SVG and accessory rendering", customSVGAndAccessoryRendering),
            ("alarm clock tuning has a wider safe range", alarmClockTuningHasWiderSafeRange),
            ("alarm clock position uses fish center", alarmClockPositionUsesFishCenter),
            ("shared alarm and timer state", sharedAlarmAndTimerState),
            ("clock sound draft preserves appearance", clockSoundDraftPreservesAppearance),
            ("clock and message styles migrate safely", visualStyleSelectionsMigrateSafely),
            ("clock persistence failure rolls back state", clockPersistenceFailureRollsBackState),
            ("clock reports unsafe state files", clockReportsUnsafeStateFiles),
            ("quick timer clock threshold", quickTimerClockThreshold),
            ("native update channel isolation", nativeUpdateChannelIsolation),
            ("native prerelease versions compare correctly", nativePrereleaseVersionsCompareCorrectly),
            ("directory install restores backup on failure", directoryInstallRestoresBackupOnFailure),
            ("native updater cleans install staging on failure", nativeUpdaterCleansInstallStagingOnFailure),
            ("single instance lock", singleInstanceLock),
            ("login item setting rolls back on save failure", loginItemSettingRollsBackOnSaveFailure),
            ("dragged height preservation", draggedHeightPreservation),
            ("nearest display preserves pet height", nearestDisplayPreservesPetHeight),
            ("visit formation joins movement bounds", visitFormationJoinsMovementBounds),
            ("scene layout coordinates satellites", sceneLayoutCoordinatesSatellites),
            ("scene layout stays clear on four screen edges", sceneLayoutStaysClearOnFourScreenEdges),
            ("scene layout separates timer and visit", sceneLayoutSeparatesTimerAndVisit),
            ("scene layout avoids visit companion", sceneLayoutAvoidsVisitCompanion),
            ("overlay geometry follows current display", overlayGeometryFollowsCurrentDisplay),
            ("attached composer follows scene across displays", attachedComposerFollowsSceneAcrossDisplays),
            ("overlay hit testing leaves transparent gaps", overlayHitTestingLeavesTransparentGaps),
            ("overlay hit testing skips noninteractive layout", overlayHitTestingSkipsNoninteractiveLayout),
            ("friend messages stack and expire", friendMessagesStackAndExpire),
            ("friend speaking tokens preserve base motion", friendSpeakingTokensPreserveBaseMotion),
            ("display-paced pet motion", displayPacedPetMotion),
            ("hover and menu pause pet motion", hoverAndMenuPausePetMotion),
            ("paused bob timeline resumes without snapping", pausedBobTimelineResumesWithoutSnapping),
            ("bob visibility transitions smoothly across frame rates", bobVisibilityTransitionsSmoothlyAcrossFrameRates),
            ("primary double click stays distinct from drag", primaryDoubleClickStaysDistinctFromDrag),
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
            ("fish invite code stays hidden by default", fishInviteCodeStaysHiddenByDefault),
            ("fish vault startup never prompts", fishVaultStartupNeverPrompts),
            ("fish vault errors preserve profile state", fishVaultErrorsPreserveProfileState),
            ("fish invite validation", fishInviteValidation),
            ("fish self invite is rejected", fishSelfInviteIsRejected),
            ("fish message end-to-end encryption", fishMessageEncryption),
            ("fish visit appearance stays encrypted", fishVisitEncryption),
            ("fish history preserves unread messages", fishHistoryPersistence),
            ("fish history rejects unsafe state files", fishHistoryRejectsUnsafeStateFiles),
            ("fish message duration migrates from old preferences", fishMessageDurationMigration),
            ("fish acknowledgement waits for persistence", fishAcknowledgementWaitsForPersistence),
            ("fish polling waits for profile without losing start intent", fishPollingWaitsForProfile),
            ("fish chat preserves a changed draft", fishChatPreservesChangedDraft),
            ("fish history opens the intended contact", fishHistoryOpensIntendedContact),
            ("fish composer chooses an explicit recipient", fishComposerChoosesExplicitRecipient),
            ("task monitor drops callbacks after stop", taskMonitorDropsCallbacksAfterStop),
            ("bounded reminder history keeps recent deduplication", boundedReminderHistoryKeepsRecentDeduplication),
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

    private static func fishInviteCodeStaysHiddenByDefault() -> Bool {
        let code = "fish1_0123456789abcdefghijklmnopqrstuvwxyz"
        let hidden = FishInviteCodePresentationPolicy.displayedCode(code, revealed: false)
        let revealed = FishInviteCodePresentationPolicy.displayedCode(code, revealed: true)
        let shortSecret = FishInviteCodePresentationPolicy.displayedCode("secret", revealed: false)
        return FishInviteCodePresentationPolicy.displayedCode("", revealed: false) == nil
            && hidden == "fish1_0123…uvwxyz"
            && hidden != code
            && revealed == code
            && shortSecret != "secret"
            && !FishInviteCodePresentationPolicy.shouldResetReveal(
                previousCode: code, nextCode: code, windowReopened: false
            )
            && FishInviteCodePresentationPolicy.shouldResetReveal(
                previousCode: code, nextCode: code + "x", windowReopened: false
            )
            && FishInviteCodePresentationPolicy.shouldResetReveal(
                previousCode: code, nextCode: code, windowReopened: true
            )
    }

    private static func fishVaultStartupNeverPrompts() -> Bool {
        let startup = FishMessengerVaultInteractionPolicy.nonInteractive
        let startupContext = startup.authenticationContext()
        let interactiveReason = "Allow Blobfish to access your existing fish-message identity."
        let interactive = FishMessengerVaultInteractionPolicy.interactive(localizedReason: interactiveReason)
        let interactiveContext = interactive.authenticationContext()
        return !startup.permitsInteraction
            && startupContext.interactionNotAllowed
            && interactive.permitsInteraction
            && !interactiveContext.interactionNotAllowed
            && interactiveContext.localizedReason == interactiveReason
    }

    private static func fishVaultErrorsPreserveProfileState() -> Bool {
        let diagnostic = FishMessengerVaultError.keychain(errSecInteractionNotAllowed).localizedDescription
        return FishMessengerVaultStatePolicy.state(for: errSecItemNotFound) == .notConfigured
            && FishMessengerVaultStatePolicy.state(for: errSecInteractionNotAllowed) == .authorizationRequired
            && FishMessengerVaultStatePolicy.state(for: errSecInteractionRequired) == .authorizationRequired
            && FishMessengerVaultStatePolicy.state(for: errSecDatabaseLocked) == .locked
            && FishMessengerVaultStatePolicy.state(for: FishMessengerVaultError.invalidState) == .corrupt
            && FishMessengerVaultStatePolicy.state(for: errSecNotAvailable) == .unavailable
            && diagnostic.contains(String(errSecInteractionNotAllowed))
            && !diagnostic.contains("profile-v1")
            && !diagnostic.contains("privateKey")
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
            let loaded = try store.load()
            return loaded.0 == .defaults && loaded.1 == [record] && loaded.1.first?.isRead == false
        }
    }

    private static func fishHistoryRejectsUnsafeStateFiles() throws -> Bool {
        try withPrivateDirectory { directory in
            let file = directory.appendingPathComponent("fish-friends.json")
            try Data("{}".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            do {
                _ = try FishFriendStore(directoryURL: directory).load()
                return false
            } catch FishFriendStore.StoreError.invalidStateFile {
                return true
            }
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

    private static func fishAcknowledgementWaitsForPersistence() -> Bool {
        let failed = Set(FishRelayAcknowledgementPolicy.resolved(
            immediatelySafe: ["rejected", "duplicate"],
            requiringPersistence: ["new-message", "new-message-copy"],
            persistenceSucceeded: false
        ))
        let saved = Set(FishRelayAcknowledgementPolicy.resolved(
            immediatelySafe: ["rejected", "duplicate"],
            requiringPersistence: ["new-message", "new-message-copy"],
            persistenceSucceeded: true
        ))
        return failed == ["rejected", "duplicate"]
            && saved == ["rejected", "duplicate", "new-message", "new-message-copy"]
    }

    private static func fishPollingWaitsForProfile() -> Bool {
        !FishMessengerPollingPolicy.shouldSchedule(
            startRequested: true,
            hasProfile: false,
            hasTimer: false
        )
            && FishMessengerPollingPolicy.shouldSchedule(
                startRequested: true,
                hasProfile: true,
                hasTimer: false
            )
            && !FishMessengerPollingPolicy.shouldSchedule(
                startRequested: true,
                hasProfile: true,
                hasTimer: true
            )
            && !FishMessengerPollingPolicy.shouldSchedule(
                startRequested: false,
                hasProfile: true,
                hasTimer: false
            )
    }

    private static func fishChatPreservesChangedDraft() -> Bool {
        let sentContactID = UUID()
        return FishChatDraftPolicy.shouldClear(
            currentDraft: "原消息",
            draftAtSend: "原消息",
            selectedContactID: sentContactID,
            sentContactID: sentContactID
        )
            && !FishChatDraftPolicy.shouldClear(
                currentDraft: "新消息",
                draftAtSend: "原消息",
                selectedContactID: sentContactID,
                sentContactID: sentContactID
            )
            && !FishChatDraftPolicy.shouldClear(
                currentDraft: "原消息",
                draftAtSend: "原消息",
                selectedContactID: UUID(),
                sentContactID: sentContactID
            )
            && String(repeating: "鱼", count: 334).utf8.count > FishMessage.maximumTextBytes
    }

    private static func fishHistoryOpensIntendedContact() -> Bool {
        let first = UUID(), second = UUID(), missing = UUID()
        return FishHistorySelectionPolicy.select(
            availableContactIDs: [first, second],
            requestedContactID: second,
            newestUnreadContactID: first,
            currentContactID: first,
            preferUnread: true
        ) == second
            && FishHistorySelectionPolicy.select(
                availableContactIDs: [first, second],
                requestedContactID: missing,
                newestUnreadContactID: second,
                currentContactID: first,
                preferUnread: true
            ) == second
            && FishHistorySelectionPolicy.select(
                availableContactIDs: [first],
                requestedContactID: nil,
                newestUnreadContactID: nil,
                currentContactID: second,
                preferUnread: false
            ) == first
    }

    private static func fishComposerChoosesExplicitRecipient() -> Bool {
        let first = UUID(), active = UUID(), preferred = UUID(), missing = UUID()
        return FishComposeRecipientPolicy.select(
            availableContactIDs: [first, active, preferred],
            preferredContactID: preferred,
            activeVisitContactID: active,
            currentContactID: first
        ) == preferred
            && FishComposeRecipientPolicy.select(
                availableContactIDs: [first, active],
                preferredContactID: missing,
                activeVisitContactID: active,
                currentContactID: first
            ) == active
            && FishComposeRecipientPolicy.select(
                availableContactIDs: [first],
                preferredContactID: nil,
                activeVisitContactID: nil,
                currentContactID: missing
            ) == first
    }

    private static func hoverAndMenuPausePetMotion() -> Bool {
        !PetMovementPause.shouldPause(hovering: false, menuOpen: false, interacting: false, dragging: false)
            && PetMovementPause.shouldPause(hovering: true, menuOpen: false, interacting: false, dragging: false)
            && PetMovementPause.shouldPause(hovering: false, menuOpen: true, interacting: false, dragging: false)
            && PetMovementPause.shouldPause(hovering: false, menuOpen: false, interacting: true, dragging: false)
            && PetMovementPause.shouldPause(hovering: false, menuOpen: false, interacting: false, dragging: true)
    }

    private static func pausedBobTimelineResumesWithoutSnapping() -> Bool {
        let beforePause = 0.225
        let offsetBeforePause = PetMotionTiming.swimOffset(elapsed: beforePause)
        let whilePaused = PetMotionTiming.advancedBobElapsed(
            current: beforePause,
            frameElapsed: 10,
            paused: true
        )
        let resumed = PetMotionTiming.advancedBobElapsed(
            current: whilePaused,
            frameElapsed: 1.0 / PetMotionTiming.framesPerSecond,
            paused: false
        )
        let offsetAfterResume = PetMotionTiming.swimOffset(elapsed: resumed)
        let clampedLongFrame = PetMotionTiming.advancedBobElapsed(
            current: resumed,
            frameElapsed: 5,
            paused: false
        )
        return whilePaused == beforePause
            && PetMotionTiming.swimOffset(elapsed: whilePaused) == offsetBeforePause
            && resumed > whilePaused
            && abs(offsetAfterResume - offsetBeforePause) < 0.5
            && abs(clampedLongFrame - resumed - 0.05) < 0.000_001
    }

    private static func bobVisibilityTransitionsSmoothlyAcrossFrameRates() -> Bool {
        func samples(fps: Int, paused: Bool, initial: CGFloat) -> [CGFloat] {
            var value = initial
            return (0..<Int(PetMotionTiming.bobVisibilityTransitionDuration * Double(fps))).map { _ in
                value = PetMotionTiming.transitionedBobVisibility(
                    current: value,
                    frameElapsed: 1.0 / Double(fps),
                    paused: paused
                )
                return value
            }
        }

        let pauseAt60 = samples(fps: 60, paused: true, initial: 1)
        let pauseAt120 = samples(fps: 120, paused: true, initial: 1)
        let resumeAt60 = samples(fps: 60, paused: false, initial: 0)
        guard let firstPaused = pauseAt60.first,
              let firstResumed = resumeAt60.first,
              let paused60 = pauseAt60.last,
              let paused120 = pauseAt120.last,
              let resumed60 = resumeAt60.last else { return false }
        let pauseIsMonotonic = zip(pauseAt60, pauseAt60.dropFirst()).allSatisfy { pair in
            pair.0 >= pair.1
        }
        let resumeIsMonotonic = zip(resumeAt60, resumeAt60.dropFirst()).allSatisfy { pair in
            pair.0 <= pair.1
        }
        let rawBob = PetMotionTiming.swimOffset(elapsed: 0.225)
        let ownerBob = rawBob * firstPaused
        let guestBob = rawBob * firstPaused
        return firstPaused > 0 && firstPaused < 1
            && firstResumed > 0 && firstResumed < 1
            && pauseIsMonotonic && resumeIsMonotonic
            && abs(paused60 - paused120) < 0.000_001
            && paused60 < 0.000_001
            && resumed60 > 0.999_999
            && ownerBob == guestBob
    }

    private static func primaryDoubleClickStaysDistinctFromDrag() -> Bool {
        let single = PetPrimaryClickIntentPolicy.resolve(dragDistance: 0, clickCount: 1)
        let double = PetPrimaryClickIntentPolicy.resolve(dragDistance: 0, clickCount: 2)
        let nearThreshold = PetPrimaryClickIntentPolicy.resolve(dragDistance: 3.99, clickCount: 2)
        let draggedSecondClick = PetPrimaryClickIntentPolicy.resolve(dragDistance: 4.01, clickCount: 2)
        return single == .singleClick
            && double == .doubleClick
            && nearThreshold == .doubleClick
            && draggedSecondClick == .drag
            && !PetPrimaryClickIntentPolicy.cancelsPendingSingle(single)
            && PetPrimaryClickIntentPolicy.cancelsPendingSingle(double)
            && PetPrimaryClickIntentPolicy.cancelsPendingSingle(draggedSecondClick)
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
                && result.config.pet.flipOnBounce
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

    private static func quickSettingsMergePreservesUnrelatedDraft() -> Bool {
        var runtime = AppConfig.defaults
        runtime.pet.roamWhenNoTasks = false
        runtime.pet.roamWhenTasks = true
        runtime.pet.flipOnBounce = false
        runtime.performance.panelEnabled = true
        runtime.startup.launchAtLogin = true
        var draft = AppConfig.defaults
        draft.pet.speed = 9.5
        draft.language.idleEnabled = false
        let merged = QuickSettingsDraftMerge.merge(runtime: runtime, into: draft)
        return !merged.pet.roamWhenNoTasks
            && merged.pet.roamWhenTasks
            && !merged.pet.flipOnBounce
            && merged.performance.panelEnabled
            && merged.startup.launchAtLogin
            && merged.pet.speed == 9.5
            && !merged.language.idleEnabled
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
        let clockIDs = Set(accessories.filter { $0.manifest.slot == "clock" }.map(\.id))
        let indicatorIDs = Set(accessories.filter { $0.manifest.slot == "message-indicator" }.map(\.id))
        let hasClock = Set(ClockAccessoryStyle.ids).isSubset(of: clockIDs)
        let hasIndicators = Set(FishMessageIndicatorStyle.ids).isSubset(of: indicatorIDs)
        let restingFaceIsNeutral = !restingSVG.contains("tear") && restingSVG.contains("eye-left")
        let selectedFaceCoversEyes = !coveredSVG.contains("eye-left") && !coveredSVG.contains("tear")
        if image == nil || accessories.count < 80 || !hasClock || !hasIndicators || !restingFaceIsNeutral || !selectedFaceCoversEyes {
            print("  renderer=\(image != nil), accessories=\(accessories.count), clock=\(hasClock), indicators=\(hasIndicators), neutral=\(restingFaceIsNeutral), covered=\(selectedFaceCoversEyes)")
            return false
        }
        return true
    }

    private static func visualStyleSelectionsMigrateSafely() throws -> Bool {
        let legacyClock = Data(#"""
        {
          "alarmSound":{"enabled":true,"soundId":"Ping"},
          "timerSound":{"enabled":true,"soundId":"Glass"},
          "allowSoundDuringQuietHours":true,
          "defaultSnoozeMinutes":5
        }
        """#.utf8)
        let legacyFriends = Data(#"""
        {
          "bubbleColor":"#1F7AE8",
          "incomingSoundEnabled":true,
          "incomingSoundID":"Submarine",
          "visitsEnabled":true
        }
        """#.utf8)
        let clock = try JSONDecoder().decode(ClockState.Preferences.self, from: legacyClock)
        let friends = try JSONDecoder().decode(FishFriendPreferences.self, from: legacyFriends)
        return clock.effectiveAlarmAccessoryID == ClockAccessoryStyle.defaultID
            && friends.effectiveMessageIndicatorID == FishMessageIndicatorStyle.defaultID
            && ClockAccessoryStyle.normalized("unknown") == ClockAccessoryStyle.defaultID
            && FishMessageIndicatorStyle.normalized("unknown") == FishMessageIndicatorStyle.defaultID
    }

    private static func clockSoundDraftPreservesAppearance() -> Bool {
        var preferences = ClockState.empty.preferences
        preferences.alarmAccessoryID = "alarm-clock-plum-night"
        preferences.defaultSnoozeMinutes = 12
        var draft = ClockSoundPreferencesDraft(preferences)
        draft.alarmSound.soundId = "Bottle"
        draft.timerSound.enabled = false
        draft.allowSoundDuringQuietHours = false
        let merged = draft.applying(to: preferences)
        return merged.alarmAccessoryID == "alarm-clock-plum-night"
            && merged.defaultSnoozeMinutes == 12
            && merged.alarmSound.soundId == "Bottle"
            && merged.timerSound.enabled == false
            && merged.allowSoundDuringQuietHours == false
    }

    private static func alarmClockTuningHasWiderSafeRange() -> Bool {
        let specification: JSONValue = .object([
            "offsetX": .number(96),
            "offsetY": .number(-74),
            "width": .number(0.5),
            "height": .number(1.8),
        ])
        let clock = AccessoryTuning(specification, accessoryID: "alarm-clock-seafoam")
        let ordinary = AccessoryTuning(specification, accessoryID: "crown")
        let clampedClock = AccessoryTuning(.object([
            "offsetX": .number(999),
            "offsetY": .number(-999),
        ]), accessoryID: "alarm-clock")
        return clock.offsetX == 96
            && clock.offsetY == -74
            && clock.width == 1
            && clock.height == 1
            && ordinary.offsetX == 30
            && ordinary.offsetY == -30
            && ordinary.width == 0.5
            && ordinary.height == 1.8
            && clampedClock.offsetX == 240
            && clampedClock.offsetY == -180
    }

    private static func alarmClockPositionUsesFishCenter() -> Bool {
        let container = CGRect(x: 0, y: 0, width: 340, height: 165)
        let character = CGRect(x: 117.5, y: 10, width: 105, height: 90)
        let canvas = CGRect(x: 0, y: 0, width: 140, height: 120)
        let size = CGSize(width: 38, height: 38)
        let centered = ClockAccessoryPositionGeometry.centeredRect(
            offsetX: 0, offsetY: 0, canvas: canvas,
            characterBounds: character, containerBounds: container, renderedSize: size
        )
        let farTopRight = ClockAccessoryPositionGeometry.centeredRect(
            offsetX: 999, offsetY: -999, canvas: canvas,
            characterBounds: character, containerBounds: container, renderedSize: size
        )
        let farBottomLeft = ClockAccessoryPositionGeometry.centeredRect(
            offsetX: -999, offsetY: 999, canvas: canvas,
            characterBounds: character, containerBounds: container, renderedSize: size
        )
        return abs(centered.midX - character.midX) < 0.001
            && abs(centered.midY - character.midY) < 0.001
            && abs(farTopRight.maxX - container.maxX) < 0.001
            && abs(farTopRight.maxY - container.maxY) < 0.001
            && abs(farBottomLeft.minX - container.minX) < 0.001
            && abs(farBottomLeft.minY - container.minY) < 0.001
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
            preferences.alarmAccessoryID = "alarm-clock-honey"
            try service.updatePreferences(preferences)
            let reloaded = ClockService(directoryURL: directory)
            let file = directory.appendingPathComponent("clock-state.json")
            var info = stat()
            guard reloaded.state.alarms.first?.time == "09:30"
                && reloaded.state.timer?.state == "running"
                && reloaded.state.preferences.alarmSound.soundId == "Bottle"
                && reloaded.state.preferences.effectiveAlarmAccessoryID == "alarm-clock-honey"
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

    private static func clockPersistenceFailureRollsBackState() throws -> Bool {
        try withPrivateDirectory { directory in
            let blocker = directory.appendingPathComponent("not-a-directory")
            try Data("blocker".utf8).write(to: blocker)

            let controls = ClockService(directoryURL: blocker, initialState: .empty, nowMs: 1_000)
            do {
                try controls.createAlarm(label: "should-not-stick", mode: "daily", time: "09:00", date: nil, weekdays: [])
                return false
            } catch {
                guard controls.state.alarms.isEmpty else { return false }
            }

            var dueState = ClockState.empty
            dueState.timer = .init(
                id: "timer:test", label: "durable first", durationMs: 500,
                state: "running", createdAtMs: 1_000, dueAtMs: 1_500,
                remainingMs: nil, source: ClockTimerSource.quick
            )
            let polling = ClockService(directoryURL: blocker, initialState: dueState, nowMs: 1_000)
            var dueEvents = 0
            var persistenceErrors = 0
            polling.onEvent = { event, _ in
                if case .timerDue = event { dueEvents += 1 }
            }
            polling.onError = { _ in persistenceErrors += 1 }
            polling.poll(nowMs: 2_000)
            polling.poll(nowMs: 3_000)
            return polling.state.timer?.id == "timer:test"
                && polling.state.alerts.isEmpty
                && dueEvents == 0
                && persistenceErrors == 1
        }
    }

    private static func clockReportsUnsafeStateFiles() throws -> Bool {
        try withPrivateDirectory { directory in
            let file = directory.appendingPathComponent("clock-state.json")
            try Data("{}".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            let service = ClockService(directoryURL: directory, nowMs: 1_000)
            var errors = 0
            service.onError = { _ in errors += 1 }
            return service.state == .empty && errors == 1
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
        func makeLayout(companion: NSRect?) -> PetSceneLayout {
            PetSceneLayoutCoordinator.layout(PetSceneLayoutInput(
                canvas: canvas,
                characterBounds: character,
                companionBounds: companion,
                timerSize: nil,
                visitStatusSize: nil,
                clockAlertSize: nil,
                taskStackSize: nil,
                ownerSpeechSize: nil,
                ownerFriendBubbleSizes: [
                    NSSize(width: 120, height: 30),
                    NSSize(width: 130, height: 34),
                ],
                visitorFriendBubbleSizes: [],
                performancePanelSize: panelSize,
                performancePanelSide: "left",
                performancePanelVerticalPosition: 0.5,
                performancePanelDistance: 6
            ))
        }
        let layout = makeLayout(companion: nil)
        let companion = NSRect(x: 45, y: 10, width: 65, height: 80)
        let companionLayout = makeLayout(companion: companion)
        guard let left = layout.performancePanelRect,
              let avoidingCompanion = companionLayout.performancePanelRect else { return false }
        let bubbles = layout.ownerFriendBubbleRects
        return abs(character.minX - left.maxX - PetSceneLayoutCoordinator.satelliteGap) < 0.001
            && !avoidingCompanion.intersects(companion)
            && !avoidingCompanion.intersects(character)
            && bubbles.count == 2
            && bubbles[0].minY > bubbles[1].maxY
            && bubbles.allSatisfy { canvas.insetBy(dx: 8, dy: 8).contains($0) }
    }

    private static func sceneLayoutStaysClearOnFourScreenEdges() -> Bool {
        let canvas = NSRect(x: 0, y: 0, width: 800, height: 600)
        let characters = [
            NSRect(x: 8, y: 255, width: 105, height: 90),
            NSRect(x: 687, y: 255, width: 105, height: 90),
            NSRect(x: 347, y: 8, width: 105, height: 90),
            NSRect(x: 347, y: 502, width: 105, height: 90),
        ]
        return characters.allSatisfy { character in
            let layout = fullSceneLayout(canvas: canvas, character: character, companion: nil)
            return sceneLayoutIsContainedAndDisjoint(layout, canvas: canvas, formation: character)
                && layout.ownerFriendBubbleRects.count == 2
                && squaredRectDistance(layout.ownerFriendBubbleRects[1], character)
                    <= squaredRectDistance(layout.ownerFriendBubbleRects[0], character)
        }
    }

    private static func sceneLayoutSeparatesTimerAndVisit() -> Bool {
        let canvas = NSRect(x: 0, y: 0, width: 800, height: 600)
        let character = NSRect(x: 347, y: 8, width: 105, height: 90)
        let layout = fullSceneLayout(canvas: canvas, character: character, companion: nil)
        guard let timer = layout.timerRect, let visit = layout.visitStatusRect else { return false }
        return !timer.intersects(visit)
            && abs(timer.midY - visit.midY) < 0.001
            && visit.minX - timer.maxX >= PetSceneLayoutCoordinator.satelliteGap
    }

    private static func sceneLayoutAvoidsVisitCompanion() -> Bool {
        let canvas = NSRect(x: 0, y: 0, width: 800, height: 600)
        let character = NSRect(x: 280, y: 255, width: 105, height: 90)
        let companion = NSRect(x: 405, y: 260, width: 82, height: 79)
        let formation = character.union(companion)
        let layout = fullSceneLayout(canvas: canvas, character: character, companion: companion)
        return sceneLayoutIsContainedAndDisjoint(layout, canvas: canvas, formation: formation)
            && layout.visitorFriendBubbleRects.count == 1
    }

    private static func overlayGeometryFollowsCurrentDisplay() -> Bool {
        let left = NSRect(x: -1_280, y: 0, width: 1_280, height: 800)
        let primary = NSRect(x: 0, y: 23, width: 1_440, height: 877)
        let formation = NSRect(x: -160, y: 240, width: 188, height: 95)
        guard PetOverlayScreenGeometry.visibleFrame(
            for: formation,
            from: [primary, left]
        ) == left else { return false }
        let local = PetOverlayScreenGeometry.localRect(
            for: NSRect(x: -150, y: 250, width: 105, height: 90),
            visibleFrame: left
        )
        let scene = PetOverlayScreenGeometry.sceneFrame(
            around: NSRect(x: -150, y: 250, width: 105, height: 90),
            inside: left
        )
        let sceneLocal = PetOverlayScreenGeometry.localRect(
            for: NSRect(x: -150, y: 250, width: 105, height: 90),
            visibleFrame: scene
        )
        return local == NSRect(x: 1_130, y: 250, width: 105, height: 90)
            && left.contains(scene)
            && scene.size == PetOverlayScreenGeometry.maximumSceneSize
            && scene.contains(NSRect(x: -150, y: 250, width: 105, height: 90))
            && NSRect(origin: .zero, size: scene.size).contains(sceneLocal)
    }

    private static func attachedComposerFollowsSceneAcrossDisplays() -> Bool {
        let primaryScreen = NSRect(x: 0, y: 23, width: 1_440, height: 877)
        let leftScreen = NSRect(x: -1_280, y: 0, width: 1_280, height: 800)
        let highScreen = NSRect(x: 1_440, y: 180, width: 1_920, height: 1_080)
        let screens = [primaryScreen, leftScreen, highScreen]
        let windowSize = NSSize(width: 460, height: 180)
        let edgeCharacters = [
            NSRect(x: 12, y: 390, width: 105, height: 90),
            NSRect(x: 1_323, y: 390, width: 105, height: 90),
            NSRect(x: 668, y: 27, width: 105, height: 90),
            NSRect(x: 668, y: 806, width: 105, height: 90),
        ]
        let edgesStayVisible = edgeCharacters.allSatisfy { character in
            guard let anchor = PetAttachedWindowGeometry.anchor(
                primaryFrame: character,
                formationFrame: character,
                visibleFrames: screens
            ) else { return false }
            let frame = PetAttachedWindowGeometry.frame(windowSize: windowSize, anchor: anchor)
            return anchor.visibleFrame == primaryScreen
                && primaryScreen.contains(frame)
                && !frame.intersects(character)
        }
        let leftCharacter = NSRect(x: -1_210, y: 320, width: 105, height: 90)
        let highCharacter = NSRect(x: 1_700, y: 1_090, width: 105, height: 90)
        guard let leftAnchor = PetAttachedWindowGeometry.anchor(
            primaryFrame: leftCharacter,
            formationFrame: leftCharacter,
            visibleFrames: screens
        ), let highAnchor = PetAttachedWindowGeometry.anchor(
            primaryFrame: highCharacter,
            formationFrame: highCharacter,
            visibleFrames: screens
        ) else { return false }
        let leftFrame = PetAttachedWindowGeometry.frame(windowSize: windowSize, anchor: leftAnchor)
        let highFrame = PetAttachedWindowGeometry.frame(windowSize: windowSize, anchor: highAnchor)
        let hiddenFrame = leftFrame.offsetBy(dx: 20, dy: 0)
        return edgesStayVisible
            && leftAnchor.visibleFrame == leftScreen
            && leftScreen.contains(leftFrame)
            && highAnchor.visibleFrame == highScreen
            && highScreen.contains(highFrame)
            && !PetAttachedWindowGeometry.shouldReposition(
                isWindowVisible: false,
                currentFrame: leftFrame,
                proposedFrame: hiddenFrame
            )
            && PetAttachedWindowGeometry.shouldReposition(
                isWindowVisible: false,
                force: true,
                currentFrame: leftFrame,
                proposedFrame: hiddenFrame
            )
            && PetAttachedWindowGeometry.shouldReposition(
                isWindowVisible: true,
                currentFrame: leftFrame,
                proposedFrame: hiddenFrame
            )
    }

    private static func overlayHitTestingLeavesTransparentGaps() -> Bool {
        let rects = [
            NSRect(x: 10, y: 10, width: 40, height: 30),
            NSRect(x: 150, y: 120, width: 50, height: 40),
        ]
        return PetOverlayHitTesting.contains(NSPoint(x: 20, y: 20), in: rects)
            && PetOverlayHitTesting.contains(NSPoint(x: 180, y: 140), in: rects)
            && !PetOverlayHitTesting.contains(NSPoint(x: 100, y: 80), in: rects)
    }

    private static func overlayHitTestingSkipsNoninteractiveLayout() -> Bool {
        !PetOverlayHitTesting.needsSceneLayout(
            hasClockAlert: false,
            unreadCount: 0,
            hasClickableMessengerSpeech: false,
            friendBubbleCount: 0
        )
            && PetOverlayHitTesting.needsSceneLayout(
                hasClockAlert: false,
                unreadCount: 1,
                hasClickableMessengerSpeech: false,
                friendBubbleCount: 0
            )
            && PetOverlayHitTesting.needsSceneLayout(
                hasClockAlert: false,
                unreadCount: 0,
                hasClickableMessengerSpeech: true,
                friendBubbleCount: 0
            )
            && PetOverlayHitTesting.needsSceneLayout(
                hasClockAlert: false,
                unreadCount: 0,
                hasClickableMessengerSpeech: false,
                friendBubbleCount: 1
            )
    }

    private static func fullSceneLayout(
        canvas: NSRect,
        character: NSRect,
        companion: NSRect?
    ) -> PetSceneLayout {
        PetSceneLayoutCoordinator.layout(PetSceneLayoutInput(
            canvas: canvas,
            characterBounds: character,
            companionBounds: companion,
            timerSize: NSSize(width: 80, height: 25),
            visitStatusSize: NSSize(width: 166, height: 21),
            clockAlertSize: NSSize(width: 276, height: 70),
            taskStackSize: NSSize(width: 294, height: 61),
            ownerSpeechSize: NSSize(width: 240, height: 50),
            ownerFriendBubbleSizes: [
                NSSize(width: 180, height: 42),
                NSSize(width: 190, height: 46),
            ],
            visitorFriendBubbleSizes: [NSSize(width: 170, height: 44)],
            performancePanelSize: NSSize(width: 58, height: 90),
            performancePanelSide: "left",
            performancePanelVerticalPosition: 0.5,
            performancePanelDistance: 6
        ))
    }

    private static func sceneLayoutIsContainedAndDisjoint(
        _ layout: PetSceneLayout,
        canvas: NSRect,
        formation: NSRect
    ) -> Bool {
        let container = canvas.insetBy(
            dx: PetSceneLayoutCoordinator.canvasInset,
            dy: PetSceneLayoutCoordinator.canvasInset
        )
        let rects = layout.overlayRects
        guard rects.allSatisfy({ container.contains($0) && !$0.intersects(formation) }) else {
            return false
        }
        for leftIndex in rects.indices {
            for rightIndex in rects.indices where rightIndex > leftIndex {
                if rects[leftIndex].intersects(rects[rightIndex]) { return false }
            }
        }
        return true
    }

    private static func squaredRectDistance(_ left: NSRect, _ right: NSRect) -> CGFloat {
        let dx = max(0, max(left.minX - right.maxX, right.minX - left.maxX))
        let dy = max(0, max(left.minY - right.maxY, right.minY - left.maxY))
        return dx * dx + dy * dy
    }

    private static func friendMessagesStackAndExpire() -> Bool {
        let now = Date(timeIntervalSince1970: 1_000)
        let contactID = UUID()
        var stack: [PetMessageBubble] = []
        let specs: [(String, PetMessageSpeaker, TimeInterval)] = [
            ("owner-0", .owner, 7),
            ("visitor-0", .visitor, 8),
            ("owner-1", .owner, 1),
            ("visitor-1", .visitor, 10),
            ("owner-2", .owner, 8),
            ("visitor-2", .visitor, 2),
            ("owner-3", .owner, 9),
            ("visitor-3", .visitor, 11),
        ]
        var messageIDs: [String: UUID] = [:]
        for (text, speaker, duration) in specs {
            let id = UUID()
            messageIDs[text] = id
            stack = PetMessageBubbleStack.inserting(
                PetMessageBubble(
                    id: id,
                    contactID: contactID,
                    text: text,
                    color: nil,
                    speaker: speaker,
                    expiresAt: now.addingTimeInterval(duration)
                ),
                into: stack,
                now: now
            )
        }
        guard stack.map(\.text) == [
            "owner-1", "visitor-1", "owner-2", "visitor-2", "owner-3", "visitor-3",
        ], stack.filter({ $0.speaker == .owner }).count == 3,
           stack.filter({ $0.speaker == .visitor }).count == 3,
           stack.allSatisfy({ $0.contactID == contactID }),
           let duplicateID = messageIDs["owner-2"] else { return false }

        stack = PetMessageBubbleStack.inserting(
            PetMessageBubble(
                id: duplicateID,
                contactID: contactID,
                text: "owner-2-new",
                color: nil,
                speaker: .owner,
                expiresAt: now.addingTimeInterval(8)
            ),
            into: stack,
            now: now
        )
        let afterTwoSeconds = PetMessageBubbleStack.active(
            stack,
            now: now.addingTimeInterval(2.5)
        )
        let distantExpiry = now.addingTimeInterval(10)
        let halfFade = now.addingTimeInterval(9.5)
        return stack.filter({ $0.id == duplicateID }).map(\.text) == ["owner-2-new"]
            && afterTwoSeconds.map(\.text) == ["visitor-1", "owner-3", "visitor-3", "owner-2-new"]
            && PetMessageBubbleStack.opacity(
                distanceFromNewest: 0, expiresAt: distantExpiry, now: now
            ) == 1
            && PetMessageBubbleStack.opacity(
                distanceFromNewest: 1, expiresAt: distantExpiry, now: now
            ) == 1
            && PetMessageBubbleStack.opacity(
                distanceFromNewest: 2, expiresAt: distantExpiry, now: halfFade
            ) == 0.225
            && PetMessageBubbleStack.opacity(
                distanceFromNewest: 0, expiresAt: distantExpiry, now: distantExpiry
            ) == 0
    }

    private static func friendSpeakingTokensPreserveBaseMotion() -> Bool {
        let now = Date(timeIntervalSince1970: 2_000)
        let bubble = PetMessageBubble(
            id: UUID(),
            contactID: UUID(),
            text: "second message",
            color: nil,
            speaker: .owner,
            expiresAt: now.addingTimeInterval(20)
        )
        let first = PetSpeakingPresentationPolicy.starting(
            token: UUID(),
            text: "first",
            now: now
        )
        let second = PetSpeakingPresentationPolicy.starting(
            token: UUID(),
            text: "second message",
            now: now
        )
        let firstExpiry = first.expiresAt
        let secondExpiry = second.expiresAt
        let view = PetView(frame: NSRect(x: 0, y: 0, width: 300, height: 190))
        view.motionState = .working
        view.beginSpeakingPresentation(first)
        view.beginSpeakingPresentation(second)
        let staleTimerDidEnd = view.endSpeakingPresentation(
            token: first.token,
            now: firstExpiry
        )
        let currentSurvived = view.speakingPresentation == second
            && view.isSpeakingPresentationActive(at: firstExpiry)
        let currentTimerDidEnd = view.endSpeakingPresentation(
            token: second.token,
            now: secondExpiry
        )
        return PetSpeakingPresentationPolicy.isActive(first, now: now)
            && first.expiresAt.timeIntervalSince(now) >= PetSpeakingPresentationPolicy.minimumDuration
            && second.expiresAt.timeIntervalSince(now) <= PetSpeakingPresentationPolicy.maximumDuration
            && second.expiresAt < bubble.expiresAt
            && !PetSpeakingPresentationPolicy.shouldEnd(first, token: second.token, now: secondExpiry)
            && !staleTimerDidEnd
            && currentSurvived
            && currentTimerDidEnd
            && view.speakingPresentation == nil
            && view.motionState == .working
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

    private static func nativePrereleaseVersionsCompareCorrectly() -> Bool {
        NativeUpdater.compareVersions("2.3.0", "2.3.0-beta.1") == 1
            && NativeUpdater.compareVersions("2.3.0-beta.2", "2.3.0-beta.10") == -1
            && NativeUpdater.compareVersions("2.3.1-beta.1", "2.3.0") == 1
            && NativeUpdater.compareVersions("2.3", "2.3.0") == nil
    }

    private static func directoryInstallRestoresBackupOnFailure() throws -> Bool {
        try withPrivateDirectory { directory in
            let target = directory.appendingPathComponent("managed", isDirectory: true)
            let temporary = directory.appendingPathComponent("installing", isDirectory: true)
            let backup = directory.appendingPathComponent("backup", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
            let marker = target.appendingPathComponent("original.txt")
            try Data("original".utf8).write(to: marker)
            do {
                try RecoverableDirectoryInstaller.replace(
                    target: target,
                    with: temporary,
                    backup: backup,
                    moveIntoPlace: { _, _, _ in throw CocoaError(.fileWriteUnknown) }
                )
                return false
            } catch {
                return FileManager.default.fileExists(atPath: marker.path)
                    && !FileManager.default.fileExists(atPath: backup.path)
                    && !FileManager.default.fileExists(atPath: temporary.path)
            }
        }
    }

    private static func nativeUpdaterCleansInstallStagingOnFailure() throws -> Bool {
        try withPrivateDirectory { directory in
            let candidate = directory.appendingPathComponent("candidate.app", isDirectory: true)
            try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
            try Data("candidate".utf8).write(to: candidate.appendingPathComponent("marker.txt"))
            let target = directory.appendingPathComponent("水滴鱼.app", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            let marker = target.appendingPathComponent("original.txt")
            try Data("original".utf8).write(to: marker)

            do {
                _ = try NativeUpdater.installVerifiedBundle(
                    at: candidate,
                    in: directory,
                    currentBundle: candidate,
                    replace: { _, _, _ in throw CocoaError(.fileWriteUnknown) }
                )
                return false
            } catch {
                let leftovers = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                ).filter { $0.lastPathComponent.hasPrefix(".水滴鱼-installing-") }
                return leftovers.isEmpty && FileManager.default.fileExists(atPath: marker.path)
            }
        }
    }

    private static func taskMonitorDropsCallbacksAfterStop() throws -> Bool {
        try withPrivateDirectory { directory in
            let monitor = TaskMonitor(directoryURL: directory)
            var updates = 0
            monitor.onUpdate = { _ in updates += 1 }
            monitor.start()
            monitor.stop()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            guard updates == 0 else { return false }

            monitor.start()
            monitor.start()
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            monitor.stop()
            return updates == 1
        }
    }

    private static func boundedReminderHistoryKeepsRecentDeduplication() -> Bool {
        var history = BoundedKeyHistory(limit: 2)
        return history.insert("old")
            && history.insert("recent")
            && history.insert("newest")
            && !history.insert("recent")
            && !history.insert("newest")
            && history.insert("old")
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

    private static func loginItemSettingRollsBackOnSaveFailure() -> Bool {
        var systemEnabled = false
        var savedEnabled = false
        do {
            try LoginItemSettingTransaction.apply(
                previous: false,
                desired: true,
                updateSystem: { systemEnabled = $0 },
                saveConfiguration: { enabled in
                    savedEnabled = enabled
                    throw CocoaError(.fileWriteUnknown)
                }
            )
            return false
        } catch {
            return !systemEnabled && savedEnabled
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
        func rect(side: String, verticalPosition: Double, distance: Double) -> CGRect? {
            PetSceneLayoutCoordinator.layout(PetSceneLayoutInput(
                canvas: canvas,
                characterBounds: character,
                companionBounds: nil,
                timerSize: nil,
                visitStatusSize: nil,
                clockAlertSize: nil,
                taskStackSize: nil,
                ownerSpeechSize: nil,
                ownerFriendBubbleSizes: [],
                visitorFriendBubbleSizes: [],
                performancePanelSize: PerformancePanelGeometry.size(for: character),
                performancePanelSide: side,
                performancePanelVerticalPosition: verticalPosition,
                performancePanelDistance: distance
            )).performancePanelRect
        }
        guard let lowerLeft = rect(side: "left", verticalPosition: 0, distance: 6),
              let upperRight = rect(side: "right", verticalPosition: 1, distance: 6),
              let clamped = rect(side: "left", verticalPosition: 5, distance: 6),
              let nearby = rect(side: "left", verticalPosition: 0.5, distance: 2),
              let distant = rect(side: "left", verticalPosition: 0.5, distance: 28) else { return false }
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
