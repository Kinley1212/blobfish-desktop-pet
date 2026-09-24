import AppKit
import Foundation
import SwiftUI

private final class ChatHTTPFixture: URLProtocol {
    static var status = 200
    static var body = Data()
    static var declaredLength: Int?
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        var headers = ["Content-Type": "application/json"]
        if let length = Self.declaredLength { headers["Content-Length"] = String(length) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor private final class ChatFixtureTransport: AIChatTransport {
    var replies: [String]
    var calls = 0
    var inputs: [[AIChatMessage]] = []
    var failure: Error?
    var delay: UInt64 = 10_000_000
    init(_ replies: [String]) { self.replies = replies }
    func complete(configuration: AIChatConfiguration, key: String, messages: [AIChatMessage]) async throws -> String {
        calls += 1
        inputs.append(messages)
        // Deliberately ignore cancellation to exercise the late-result generation guard.
        try? await Task.sleep(nanoseconds: delay)
        if let failure { throw failure }
        return replies.isEmpty ? "invalid" : replies.removeFirst()
    }
}

extension SelfCheck {
    @MainActor static func aiChatTimeContext() throws -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("ai-chat-memory.json")
        let legacyID = UUID()
        let legacy: [String: Any] = [
            "entries": [["characterID": "blobfish", "languageID": "blobfish-zh-TW", "user": "明天有事", "fish": "……知道了。"]],
            "facts": [["id": legacyID.uuidString, "text": "旧记忆"]]
        ]
        try JSONSerialization.data(withJSONObject: legacy).write(to: file)
        let store = AIChatMemoryStore(directory: directory)
        guard !store.loadFailed, store.state.entries[0].userTime == nil, store.state.facts[0].savedAt == nil else { return false }
        let iso = ISO8601DateFormatter()
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let sent = AIChatTimestamp(date: iso.date(from: "2026-09-23T23:58:00+08:00")!, timeZone: zone)
        let reply = AIChatTimestamp(date: iso.date(from: "2026-09-24T00:02:00+08:00")!, timeZone: zone)
        let saved = AIChatTimestamp(date: iso.date(from: "2026-09-24T12:10:00+08:00")!, timeZone: zone)
        let now = AIChatTimestamp(date: iso.date(from: "2026-09-24T16:00:00+09:00")!, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        try store.record(user: "明天有面试", fish: "……陪你等。", characterID: "blobfish", languageID: "blobfish-zh-TW", userTime: sent, fishTime: reply)
        try store.remember("明天有面试", spokenAt: sent, savedAt: saved)
        let reopened = AIChatMemoryStore(directory: directory)
        guard !reopened.loadFailed, reopened.state == store.state,
              reopened.state.entries[0].userTime == nil, reopened.state.facts[0].savedAt == nil,
              reopened.state.facts[1].spokenAt == sent, reopened.state.facts[1].savedAt == saved else { return false }
        let runtime = AppRuntime(applicationSupportURL: directory)
        let pack = try runtime.catalog!.dialogue(id: "blobfish-zh-TW")
        let history = reopened.history(characterID: "blobfish", languageID: "blobfish-zh-TW")
        let messages = AIChatPrompt.messages(runtime: runtime, pack: pack, history: history, memories: reopened.state.facts,
                                            input: "重试刚才那句", now: now, inputTime: sent)
        guard messages[0].content.contains("2026-09-24T16:00:00+09:00 [Asia/Tokyo]"),
              messages.contains(where: { $0.role == "user" && $0.content.hasPrefix("[Original message time: unknown]\n明天有事") }),
              messages.contains(where: { $0.role == "assistant" && $0.content.contains("2026-09-24T00:02:00+08:00") }),
              messages.last?.content.contains("2026-09-23T23:58:00+08:00") == true else { return false }
        let notes = messages.first { $0.content.hasPrefix("Saved user notes") }!.content
        guard notes.contains("2026-09-23T23:58:00+08:00"), notes.contains("2026-09-24T12:10:00+08:00"), notes.contains("unknown") else { return false }
        // Metadata stays out of provider-specific fields and never pollutes the saved text.
        let wire = try JSONSerialization.jsonObject(with: JSONEncoder().encode(history)) as! [[String: Any]]
        guard wire.allSatisfy({ Set($0.keys) == Set(["role", "content"]) }),
              reopened.state.entries[1].user == "明天有面试" else { return false }
        // A retry after the original send retains its date, including in saved memory.
        try runtime.update { $0.aiChat = AIChatConfiguration(enabled: true, endpoint: "https://fixture.invalid/v1", model: "fixture", memoryEnabled: true) }
        let transport = ChatFixtureTransport([])
        transport.failure = AIChatError.http(503)
        let model = DialogueViewModel(runtime: runtime, pack: pack, transport: transport, keyProvider: { _ in "fixture-key" }) { _, _ in }
        model.submit("明天还有事", submittedAt: sent)
        guard spinChat(until: { !model.isBusy }), model.choices.count == 2 else { return false }
        transport.failure = nil
        transport.replies = [#"{"text":"……陪你等。","options":["好","先聊别的"],"emotion":"caring"}"#]
        model.choices[0].action()
        guard spinChat(until: { !model.isBusy }), runtime.chatMemory.state.entries.last?.userTime == sent,
              transport.inputs.last?.last?.content.contains("2026-09-23T23:58:00+08:00") == true else { return false }
        model.rememberLastInput()
        guard runtime.chatMemory.state.facts.last?.spokenAt == sent else { return false }
        let la = TimeZone(identifier: "America/Los_Angeles")!
        let before = AIChatTimestamp(date: iso.date(from: "2026-11-01T08:30:00Z")!, timeZone: la)
        let after = AIChatTimestamp(date: iso.date(from: "2026-11-01T09:30:00Z")!, timeZone: la)
        return before.label.contains("01:30:00-07:00") && after.label.contains("01:30:00-08:00")
    }

    static func aiChatCompanionSettings() throws -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = NativeConfigStore(directoryURL: directory)
        // Upgrade the shipped default through the actual loader, preserving custom interests.
        for (scope, expected) in [(AIChatConfiguration.previousTopicScope, AIChatConfiguration.defaultTopicScope),
                                  ("  动物、做饭、我的小花园  ", "动物、做饭、我的小花园"), ("", "")] {
            let data = try JSONSerialization.data(withJSONObject: ["aiChat": ["topicScope": scope, "memoryEnabled": false]])
            try data.write(to: store.fileURL)
            let loaded = store.load()
            guard loaded.warning == nil, loaded.config.aiChat.topicScope == expected,
                  !loaded.config.aiChat.enabled, !loaded.config.aiChat.memoryEnabled else { return false }
            try store.save(loaded.config)
            guard store.load().config.aiChat.topicScope == expected else { return false }
        }
        var config = AIChatConfiguration.defaults
        config.topicScope = String(repeating: "鱼", count: 400)
        do { _ = try config.validated(); return false } catch {}
        return true
    }

    static func dialogueArtworkMotion() -> Bool {
        // Chat has its own gentle artwork cycle. The attached controls use the
        // unchanged physical anchor, not this render-only offset.
        let anchor = PetSceneAnchor(primaryFrame: CGRect(x: 300, y: 300, width: 140, height: 160),
                                    formationFrame: CGRect(x: 300, y: 300, width: 140, height: 160),
                                    visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let frame = DialogueLayout.frame(size: CGSize(width: 280, height: 220), anchor: anchor)
        for (character, period, maximum) in [("blobfish", 2.4, 3.0), ("grass-buddy", 3.0, 1.5)] {
            let offsets = (0...60).map {
                PetMotionTiming.swimOffset(elapsed: Double($0) / 60 * period, characterID: character, state: .chatting)
            }
            guard offsets.min() == 0, abs((offsets.max() ?? 0) - maximum) < 0.01,
                  abs(offsets.first! - offsets.last!) < 0.01,
                  offsets.allSatisfy({ $0 >= 0 && $0 <= maximum }),
                  DialogueLayout.frame(size: CGSize(width: 280, height: 220), anchor: anchor) == frame else { return false }
        }
        return true
    }

    static func aiChatValidation() throws -> Bool {
        var config = AIChatConfiguration.defaults
        guard !config.enabled, try config.validated() == config else { return false }
        config.endpoint = "https://api.example.com/v1/chat/completions"
        config.model = "test-model"
        config.enabled = true
        _ = try config.validated()
        for endpoint in ["http://example.com/v1/chat/completions", "https://user:secret@example.com/api", "file:///tmp/a", "https://example.com/?key=secret", "https://example.com/#token"] {
            config.endpoint = endpoint
            do { _ = try config.validated(); return false } catch {}
        }
        config.endpoint = "http://127.0.0.1:1234/v1/chat/completions"
        _ = try config.validated()
        for (input, expected) in [
            ("https://api.deepseek.com", "https://api.deepseek.com/chat/completions"),
            ("https://api.deepseek.com/", "https://api.deepseek.com/chat/completions"),
            ("https://api.deepseek.com/v1", "https://api.deepseek.com/v1/chat/completions"),
            ("https://api.deepseek.com/v1/", "https://api.deepseek.com/v1/chat/completions"),
            ("https://proxy.example.com/openai/v1", "https://proxy.example.com/openai/v1/chat/completions"),
            ("https://api.deepseek.com/chat/completions", "https://api.deepseek.com/chat/completions"),
            ("https://custom.example.com/my-chat", "https://custom.example.com/my-chat")
        ] {
            config.endpoint = input
            let validated = try config.validated()
            guard validated.endpoint == input, try validated.requestURL().absoluteString == expected else { return false }
        }
        config.endpoint = "https://api.deepseek.com"
        config.model = "deepseek-flash"
        let deepSeek = try AIChatHTTPTransport.request(configuration: config, key: "test-only", messages: [.init(role: "user", content: "JSON test")])
        let body = try JSONSerialization.jsonObject(with: deepSeek.httpBody!) as! [String: Any]
        guard deepSeek.url?.path == "/chat/completions", body["model"] as? String == "deepseek-flash",
              (body["thinking"] as? [String: String])?["type"] == "disabled",
              (body["response_format"] as? [String: String])?["type"] == "json_object" else { return false }
        config.endpoint = "https://other.example.com/v1"
        let generic = try AIChatHTTPTransport.request(configuration: config, key: "test-only", messages: [])
        let genericBody = try JSONSerialization.jsonObject(with: generic.httpBody!) as! [String: Any]
        guard genericBody["thinking"] == nil, genericBody["response_format"] == nil else { return false }
        let valid = #"{"text":"……再陪我一会儿。","options":["好","去歇会儿"],"emotion":"shy"}"#
        let turn = try AIChatTurn.decode(valid, english: false)
        guard turn.face(characterID: "blobfish") == "face-shy", turn.face(characterID: "grass-buddy") == "face-grass-happy" else { return false }
        for bad in [valid.replacingOccurrences(of: "shy", with: "run-command"), valid.replacingOccurrences(of: "\"去歇会儿\"", with: "\"好\""), "not json", valid.replacingOccurrences(of: "……再陪我一会儿。", with: String(repeating: "字", count: 121))] {
            do { _ = try AIChatTurn.decode(bad, english: false); return false } catch {}
        }
        return true
    }

    static func aiChatMemoryBounds() throws -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AIChatMemoryStore(directory: directory)
        for index in 0..<(AIChatMemoryStore.entryCountLimit + 30) {
            try store.record(user: "\(index)" + String(repeating: "你好", count: 1000), fish: "……", characterID: "blobfish", languageID: "blobfish-zh-TW")
            try store.remember("\(index)" + String(repeating: "猫", count: 300))
        }
        let factCount = store.state.facts.count
        guard store.state.entries.count == AIChatMemoryStore.entryCountLimit, factCount == AIChatMemoryStore.factCountLimit,
              store.bytesUsed <= AIChatMemoryStore.fileLimit,
              store.history(characterID: "grass-buddy", languageID: "grass-buddy-en").isEmpty else { return false }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        let bytes = try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        let mode = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber
        guard bytes <= AIChatMemoryStore.fileLimit,
              AIChatMemoryStore.fileLimit * 2 <= AIChatMemoryStore.totalDiskLimit,
              store.state.entries.first?.user.hasPrefix("30你好") == true,
              store.history(characterID: "blobfish", languageID: "blobfish-zh-TW").count == 12,
              mode?.intValue == 0o600 else { return false }
        let reopened = AIChatMemoryStore(directory: directory)
        guard reopened.state == store.state, !reopened.loadFailed else { return false }
        try reopened.forget(reopened.state.facts[0].id)
        guard reopened.state.entries.isEmpty, reopened.state.facts.count == factCount - 1 else { return false }
        try reopened.clear()
        guard reopened.state.facts.isEmpty, reopened.state.entries.isEmpty else { return false }
        // Reject symlinks instead of following them or overwriting their target.
        try FileManager.default.removeItem(at: reopened.fileURL)
        let target = directory.appendingPathComponent("untouched.txt")
        try Data("sentinel".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: reopened.fileURL, withDestinationURL: target)
        let unsafe = AIChatMemoryStore(directory: directory)
        guard unsafe.loadFailed else { return false }
        do { try unsafe.remember("test"); return false } catch {}
        return try String(contentsOf: target) == "sentinel"
    }

    static func dialogueBelowPetGeometry() -> Bool {
        for visible in [CGRect(x: 0, y: 0, width: 1440, height: 875), CGRect(x: -1280, y: 50, width: 1280, height: 720)] {
            for x in [visible.minX, visible.midX, visible.maxX - 140] {
                let pet = CGRect(x: x, y: visible.minY, width: 140, height: 160)
                let anchor = PetSceneAnchor(primaryFrame: pet, formationFrame: pet, visibleFrame: visible)
                let size = CGSize(width: 280, height: 240)
                let lift = DialogueLayout.lift(size: size, anchor: anchor)
                let moved = pet.offsetBy(dx: 0, dy: lift)
                let frame = DialogueLayout.frame(size: size, anchor: .init(primaryFrame: moved, formationFrame: moved, visibleFrame: visible))
                guard visible.contains(frame), frame.maxY <= moved.minY - 9, !frame.intersects(moved) else { return false }
            }
        }
        return true
    }

    @MainActor static func aiChatLifecycle() throws -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = AppRuntime(applicationSupportURL: directory)
        let pack = try runtime.catalog!.dialogue(id: "blobfish-zh-TW")
        let reply = #"{"text":"……陪你。","options":["一起歇会儿","再聊聊"],"emotion":"caring"}"#
        let transport = ChatFixtureTransport([reply])
        var reactions: [String] = []
        let model = DialogueViewModel(runtime: runtime, pack: pack, transport: transport, keyProvider: { _ in "fixture-key" }) { text, _ in reactions.append(text) }
        guard !model.aiActive, !model.choices.isEmpty, reactions.last == model.prompt else { return false }
        model.submit("No API")
        guard transport.calls == 0 else { return false }
        try runtime.update { $0.aiChat = AIChatConfiguration(enabled: true, endpoint: "https://api.example.com/v1/chat/completions", model: "fixture", memoryEnabled: true) }
        model.synchronize(pack: pack)
        model.draft = "我喜欢猫"
        model.sendDraft()
        guard spinChat(until: { !model.isBusy }), model.prompt == "……陪你。", model.draft.isEmpty,
              model.moodFaceID == "face-coy", model.choices.count == 2, runtime.chatMemory.state.entries.count == 1 else { return false }
        model.rememberLastInput()
        guard runtime.chatMemory.state.facts.first?.text == "我喜欢猫",
              let firstEntry = runtime.chatMemory.state.entries.first,
              let userTime = firstEntry.userTime, let fishTime = firstEntry.fishTime,
              userTime.date <= fishTime.date,
              runtime.chatMemory.state.facts.first?.spokenAt == userTime,
              runtime.chatMemory.state.facts.first?.savedAt != nil else { return false }
        // One invalid format retry, then success.
        transport.replies = ["not JSON", reply]
        model.submit("继续")
        guard spinChat(until: { !model.isBusy }), transport.calls == 3, model.notice.isEmpty else { return false }
        // A newly edited draft survives a successful reply to the previous message.
        transport.replies = [reply]
        model.draft = "发出去的这句"
        model.sendDraft()
        model.draft = "下一句还没写完"
        guard spinChat(until: { !model.isBusy }), model.draft == "下一句还没写完" else { return false }
        model.draft = ""
        // Deleting memory cancels an in-flight request and clears session history.
        transport.delay = 100_000_000
        transport.replies = [reply]
        model.submit("不能在删除后记回来")
        _ = spinChat(until: { transport.calls == 5 })
        try runtime.chatMemory.clear()
        NotificationCenter.default.post(name: .aiChatMemoryCleared, object: runtime.chatMemory)
        let afterClear = model.prompt
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard model.prompt == afterClear, runtime.chatMemory.state.entries.isEmpty, !model.isBusy else { return false }
        // Network errors preserve the draft, offer retry/local fallback, and never persist a failed turn.
        transport.failure = AIChatError.http(401)
        model.submit("保留我的输入")
        guard spinChat(until: { !model.isBusy }), model.draft == "保留我的输入", !model.notice.isEmpty,
              runtime.chatMemory.state.entries.isEmpty else { return false }
        model.useLocal()
        model.startFresh()
        guard !model.aiActive, !model.choices.isEmpty else { return false }
        // Privacy off means no saved facts/history are sent, and no new records are written.
        try runtime.chatMemory.remember("private-sentinel")
        try runtime.update { $0.aiChat.memoryEnabled = false }
        model.synchronize(pack: pack)
        transport.failure = nil
        transport.replies = [reply]
        model.submit("临时聊聊")
        guard spinChat(until: { !model.isBusy }), runtime.chatMemory.state.entries.isEmpty,
              !(transport.inputs.last ?? []).contains(where: { $0.content.contains("private-sentinel") }) else { return false }
        transport.replies = [reply]
        model.draft = "还没发送的草稿"
        model.changeTopic()
        guard spinChat(until: { !model.isBusy }), model.draft == "还没发送的草稿",
              runtime.chatMemory.state.entries.isEmpty,
              transport.inputs.last?.first?.content.contains("Interaction: newTopic.") == true else { return false }
        // Opening has a different intent from changing topics and is never saved as user speech.
        try runtime.update { $0.aiChat.memoryEnabled = true }
        model.synchronize(pack: pack)
        transport.replies = [reply]
        model.openConversation()
        guard spinChat(until: { !model.isBusy }), runtime.chatMemory.state.entries.isEmpty,
              transport.inputs.last?.first?.content.contains("Interaction: opening.") == true else { return false }
        transport.replies = [reply]
        model.submit("今天有个小好消息")
        guard spinChat(until: { !model.isBusy }), runtime.chatMemory.state.entries.count == 1,
              runtime.chatMemory.state.entries[0].user == "今天有个小好消息",
              transport.inputs.last?.first?.content.contains("Interaction: reply.") == true else { return false }
        transport.replies = [reply]
        model.submit("关闭后别再说话")
        let closing = reactions.count
        model.cancel()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return reactions.count == closing && !model.isBusy
    }

    @MainActor static func aiChatContextBounds() throws -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = AppRuntime(applicationSupportURL: directory)
        let pack = try runtime.catalog!.dialogue(id: "blobfish-zh-TW")
        let history = (0..<100).map { AIChatMessage(role: $0 % 2 == 0 ? "user" : "assistant", content: String(repeating: "字", count: 4096)) }
        let messages = AIChatPrompt.messages(runtime: runtime, pack: pack, history: history, memories: (0..<50).map { AIChatMemoryState.Fact(id: UUID(), text: "\($0)" + String(repeating: "事实", count: 80), savedAt: .init(), spokenAt: .init()) }, input: "今天累了", intent: .newTopic)
        return messages.reduce(0, { $0 + $1.content.utf8.count }) <= AIChatPrompt.maximumBytes
            && messages.last?.content.hasSuffix("\n今天累了") == true
            && messages.first?.role == "system"
            && messages.first?.content.contains("zh-TW") == true
            && messages.first?.content.contains("疲憊") == true
            && messages.first?.content.contains("no prewritten topic or question bank") == true
            && messages.first?.content.contains(runtime.config.aiChat.topicScope) == true
    }

    @MainActor static func aiChatHTTPBounds() throws -> Bool {
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [ChatHTTPFixture.self]
        let transport = AIChatHTTPTransport(sessionConfiguration: session)
        let config = AIChatConfiguration(enabled: true, endpoint: "https://fixture.invalid/v1/chat/completions", model: "test", memoryEnabled: false)
        func request() -> Result<String, Error>? {
            var result: Result<String, Error>?
            Task {
                do { result = .success(try await transport.complete(configuration: config, key: "fixture-key", messages: [.init(role: "user", content: "hello")])) }
                catch { result = .failure(error) }
            }
            _ = spinChat(until: { result != nil })
            return result
        }
        ChatHTTPFixture.requests = []
        ChatHTTPFixture.status = 200
        ChatHTTPFixture.declaredLength = nil
        ChatHTTPFixture.body = Data(#"{"choices":[{"message":{"content":"fixture reply"}}]}"#.utf8)
        guard case .success("fixture reply") = request(),
              ChatHTTPFixture.requests.last?.httpMethod == "POST",
              ChatHTTPFixture.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key" else { return false }
        ChatHTTPFixture.status = 401
        guard case .failure(AIChatError.http(401)) = request() else { return false }
        ChatHTTPFixture.status = 200
        ChatHTTPFixture.declaredLength = 100_000
        guard case .failure(AIChatError.tooLarge) = request() else { return false }
        ChatHTTPFixture.declaredLength = nil
        ChatHTTPFixture.body = Data(repeating: 65, count: 70_000)
        guard case .failure(AIChatError.tooLarge) = request() else { return false }
        ChatHTTPFixture.body = Data(#"{"choices":[{"message":{"tool_calls":[]}}]}"#.utf8)
        guard case .failure(AIChatError.response) = request() else { return false }
        // Redirect rejection is independent of a provider's status/body.
        let realSession = URLSession(configuration: .ephemeral)
        defer { realSession.invalidateAndCancel() }
        let url = try config.requestURL()
        var redirected = true
        transport.urlSession(realSession, task: realSession.dataTask(with: url),
                             willPerformHTTPRedirection: HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!,
                             newRequest: URLRequest(url: URL(string: "https://other.invalid/")!)) { redirected = $0 != nil }
        return !redirected
    }

    @MainActor static func dialogueWindowLayout() throws -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = AppRuntime(applicationSupportURL: directory)
        let pack = try runtime.catalog!.dialogue(id: "blobfish-zh-TW")
        let controller = DialogueWindowController(runtime: runtime, pack: pack) { _, _ in }
        // Inspect an offscreen hosting view's layout; do not display/capture the user's desktop.
        guard let window = controller.window, let view = window.contentView else { return false }
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        view.setFrameSize(size)
        view.layoutSubtreeIfNeeded()
        func findMore(_ view: NSView) -> DialogueMoreControl.Control? {
            if let control = view as? DialogueMoreControl.Control { return control }
            return view.subviews.lazy.compactMap { findMore($0) }.first
        }
        guard let more = findMore(view), let cell = more.cell as? NSButtonCell else { return false }
        let icon = cell.imageRect(forBounds: more.bounds)
        let controlFrame = view.convert(more.bounds, from: more)
        guard abs(more.bounds.width - 28) < 1, abs(more.bounds.height - 24) < 1,
              abs(icon.midX - more.bounds.midX) < 1, abs(icon.midY - more.bounds.midY) < 1,
              abs(controlFrame.maxX - (size.width - 4 - 29)) < 1 else { return false }
        guard !window.isOpaque && !window.hasShadow && window.backgroundColor == .clear,
              !window.styleMask.contains(.titled), size.width == DialogueLayout.width, (80...330).contains(size.height) else { return false }
        try runtime.update { $0.aiChat = AIChatConfiguration(enabled: true, endpoint: "https://fixture.invalid/chat/completions", model: "test", memoryEnabled: false) }
        let aiController = DialogueWindowController(runtime: runtime, pack: pack) { _, _ in }
        guard let aiView = aiController.window?.contentView else { return false }
        aiView.layoutSubtreeIfNeeded()
        return aiView.fittingSize.width == DialogueLayout.width && (120...330).contains(aiView.fittingSize.height)
    }

    @MainActor static func dialogueOptionsCollapse() throws -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = AppRuntime(applicationSupportURL: directory)
        try runtime.update { $0.aiChat = AIChatConfiguration(enabled: true, endpoint: "https://fixture.invalid/v1", model: "fixture", memoryEnabled: false) }
        let pack = try runtime.catalog!.dialogue(id: "blobfish-zh-TW")
        let transport = ChatFixtureTransport([#"{"text":"……陪你。","options":["一起歇会儿","再聊聊"],"emotion":"caring"}"#])
        let model = DialogueViewModel(runtime: runtime, pack: pack, transport: transport, keyProvider: { _ in "fixture-key" }) { _, _ in }
        model.draft = "输入了一半的草稿"
        let host = NSHostingView(rootView: DialogueView(model: model, close: {}))
        func fittedHeight() -> CGFloat {
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            host.setFrameSize(size)
            host.layoutSubtreeIfNeeded()
            return size.height
        }
        func editor(in view: NSView) -> FishComposeTextView? {
            if let editor = view as? FishComposeTextView { return editor }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        let expanded = fittedHeight()
        guard let originalEditor = editor(in: host), originalEditor.font?.pointSize == 12,
              host.fittingSize.width == 248, model.showsChoices else { return false }
        model.toggleOptions()
        guard spinChat(until: { fittedHeight() < expanded - 40 }), !model.showsChoices,
              model.draft == "输入了一半的草稿", editor(in: host) === originalEditor,
              originalEditor.string == model.draft, transport.calls == 0 else { return false }
        let collapsed = fittedHeight()
        guard collapsed <= 80 else { return false }
        model.sendDraft()
        guard spinChat(until: { !model.isBusy }), model.optionsCollapsed, !model.showsChoices,
              model.choices.count == 2, model.draft.isEmpty, transport.calls == 1 else { return false }
        model.draft = "下一句还没写完"
        model.toggleOptions()
        guard spinChat(until: { fittedHeight() > collapsed + 40 }), model.showsChoices,
              model.draft == "下一句还没写完", editor(in: host) === originalEditor else { return false }
        model.toggleOptions()
        model.showGames()
        guard !model.aiActive, model.showsChoices, !model.choices.isEmpty, transport.calls == 1 else { return false }
        model.cancel()
        return true
    }

    @MainActor private static func spinChat(until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        return condition()
    }
}
