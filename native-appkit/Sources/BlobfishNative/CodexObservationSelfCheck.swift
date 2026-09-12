import AppKit
import Foundation

extension SelfCheck {
    static func codexHiddenQuestionsStillNotify() -> Bool {
        var thread = CodexObservedThread(id: "t", turnID: "a", state: "running", timestamp: 1000)
        thread.blockingQuestions = ["s:q"]
        let request = CodexQuestionRequest(id: "s:q", threadID: "t", turnID: "a", blocking: true, questions: [.init(id: "0", title: "Approve?", options: [])])
        let all = CodexAttentionPolicy.blockingIDs([thread])
        guard CodexAttentionPolicy.unpreviewedBlockingIDs([thread], previews: [], previous: []).count == 1,
              CodexAttentionPolicy.unpreviewedBlockingIDs([thread], previews: [request], previous: []).isEmpty,
              CodexAttentionPolicy.unpreviewedBlockingIDs([thread], previews: [], previous: all).isEmpty else { return false }
        thread.blockingQuestions = []
        return CodexAttentionPolicy.unpreviewedBlockingIDs([thread], previews: [], previous: []).isEmpty
    }

    static func codexCachePayloadBounds() throws -> Bool {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blobfish-payload-check-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sample.json")
        var thread = CodexObservedThread(id: "t", turnID: "a", state: "running", timestamp: 1000)
        thread.blockingQuestions = ["s:q"]
        let question = CodexQuestion(id: "0", title: "Safe question", options: [])
        for request in [
            CodexQuestionRequest(id: "s:q", threadID: "other-thread", turnID: "a", blocking: true, questions: [question]),
            CodexQuestionRequest(id: "s:q", threadID: "t", turnID: "old-turn", blocking: true, questions: [question]),
            CodexQuestionRequest(id: "s:q", threadID: "t", turnID: "a", blocking: true, questions: [question, question])
        ] {
            thread.questions = [request]
            guard CodexObservationFiles.write(try JSONEncoder().encode(CodexObservationSnapshot(timestamp: 1000, threads: [thread])), to: file) else { return false }
            let loaded = CodexObservationFiles.load(directory: root, now: 1001)
            guard loaded.count == 1, loaded[0].questions.isEmpty, loaded[0].blockingQuestions == ["s:q"] else { return false }
        }
        thread.state = "ended"
        thread.approvals = ["n:1"]
        guard CodexObservationFiles.write(try JSONEncoder().encode(CodexObservationSnapshot(timestamp: 1000, threads: [thread])), to: file) else { return false }
        let terminal = CodexObservationFiles.load(directory: root, now: 1001)
        guard terminal.first?.approvals.isEmpty == true, terminal.first?.blockingQuestions.isEmpty == true else { return false }
        for batch in 0..<2 {
            let threads = (0..<40).map { index -> CodexObservedThread in
                let id = "batch-\(batch)-\(index)"
                return .init(id: id, turnID: "a", state: "running", timestamp: 1000, questions: [
                    .init(id: "s:q", threadID: id, turnID: "a", blocking: false, questions: [.init(id: "0", title: String(repeating: "x", count: 8192), options: [])])
                ])
            }
            guard CodexObservationFiles.write(try JSONEncoder().encode(CodexObservationSnapshot(timestamp: 1000, threads: threads)), to: root.appendingPathComponent("batch-\(batch).json")) else { return false }
        }
        let loaded = CodexObservationFiles.load(directory: root, now: 1001)
        let textBytes = loaded.flatMap(\.questions).flatMap(\.questions).reduce(0) { $0 + $1.title.utf8.count }
        return loaded.count == 64 && textBytes <= 64 * 1024
    }

    static func codexDuplicateAndCapacityRegression() -> Bool {
        var reducer = CodexObservationReducer()
        let start: [String: Any] = ["method": "turn/started", "params": ["threadId": "t", "turn": ["id": "a"]]]
        reducer.receive(start, now: 1000, includeQuestions: true)
        let large = (0..<13).map { ["id": String($0), "question": "Question"] }
        func request(_ blocking: Bool) -> [String: Any] {
            ["id": "q", "method": "item/tool/requestUserInput", "params": ["threadId": "t", "turnId": "a", "isBlocking": blocking, "questions": large]]
        }
        reducer.receive(request(true), now: 1001, includeQuestions: true)
        guard reducer.threads["t"]?.blockingQuestions == ["s:q"], reducer.threads["t"]?.questions.isEmpty == true else { return false }
        reducer.receive(request(false), now: 1002, includeQuestions: true)
        guard reducer.threads["t"]?.blockingQuestions.isEmpty == true else { return false }
        reducer.receive(["method": "turn/completed", "params": ["threadId": "t", "turn": ["id": "a", "status": "unknown"]]], now: 1002, includeQuestions: true)
        guard reducer.threads["t"]?.state == "running" else { return false }
        let completed: [String: Any] = ["method": "turn/completed", "params": ["threadId": "t", "turn": ["id": "a", "status": "completed"]]]
        reducer.receive(completed, now: 1003, includeQuestions: true)
        let before = reducer.snapshot(now: 0)
        reducer.receive(completed, now: 9999, includeQuestions: true)
        reducer.receive(["method": "serverRequest/resolved", "params": ["threadId": "t", "requestId": "not-pending"]], now: 10000, includeQuestions: true)
        return reducer.snapshot(now: 0) == before
    }

    static func codexCrowdedCacheRecovery() throws -> Bool {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blobfish-cache-stress-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date().timeIntervalSince1970 * 1000
        let data = try JSONEncoder().encode(CodexObservationSnapshot(timestamp: now, threads: [.init(id: "fresh", turnID: "t", state: "running", timestamp: now)]))
        for index in 0..<140 {
            let url = root.appendingPathComponent("\(index)-\(UUID().uuidString.lowercased()).json")
            guard CodexObservationFiles.write(data, to: url) else { return false }
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: (now - 60_000) / 1000)], ofItemAtPath: url.path)
        }
        guard CodexObservationFiles.write(data, to: root.appendingPathComponent("live.json")) else { return false }
        let observations = CodexObservationFiles.load(directory: root, now: now)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
        return observations.map(\.id) == ["fresh"] && remaining.count == 1
    }

    static func codexSettingsRaceRegression() throws -> Bool {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blobfish-settings-race-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("codex-observations")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let now = Date().timeIntervalSince1970 * 1000
        let data = try JSONEncoder().encode(CodexObservationSnapshot(timestamp: now, threads: [.init(id: "active", turnID: "t", state: "running", timestamp: now)]))
        guard CodexObservationFiles.write(data, to: directory.appendingPathComponent("live.json")) else { return false }
        let monitor = TaskMonitor(directoryURL: root.appendingPathComponent("agent-leases"))
        var received = false, stale = false
        monitor.onCodexUpdate = { observations in received = true; stale = stale || !observations.isEmpty }
        monitor.start()
        monitor.enabledProviders = []
        monitor.showQuestions = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        monitor.stop()
        return received && !stale
    }

    static func codexObservationPolicy() throws -> Bool {
        var reducer = CodexObservationReducer()
        var now = 100_000.0
        func send(_ method: String, _ params: [String: Any], id: Any? = nil, enabled: Bool = true) {
            now += 1
            var message: [String: Any] = ["method": method, "params": params]
            message["id"] = id
            reducer.receive(message, now: now, includeQuestions: enabled)
        }
        let base: [String: Any] = ["threadId": "t1", "turnId": "turn1"]
        send("turn/started", ["threadId": "t1", "turn": ["id": "turn1"]])
        for status in ["inProgress", "approved", "denied", "timedOut", "aborted"] {
            send("item/autoApprovalReview/completed", base.merging(["review": ["status": status]]) { _, new in new })
            guard reducer.threads["t1"]?.approvals.isEmpty == true else { return false }
        }
        let legacy = TaskLease(version: 1, provider: "codex", event: .needsInput, sessionId: "t1", turnId: "turn1", title: nil, timestamp: now, startedAt: nil)
        var merged = CodexTaskProjection.merge(leases: [legacy], observations: reducer.snapshot(now: now).threads, now: now)
        guard merged.count == 1, merged[0].event == .running else { return false }
        send("item/commandExecution/requestApproval", base, id: 9)
        merged = CodexTaskProjection.merge(leases: [legacy], observations: reducer.snapshot(now: now).threads, now: now)
        guard merged[0].event == .needsInput else { return false }
        send("serverRequest/resolved", ["threadId": "t1", "requestId": 9])
        guard reducer.threads["t1"]?.approvals.isEmpty == true else { return false }
        let questions: [[String: Any]] = [
            ["id": "a", "question": "第一题", "options": [["label": "选项一", "description": "细节"]]],
            ["id": "b", "question": "第二题", "options": NSNull()],
            ["id": "c", "question": "第三题", "options": []],
            ["id": "secret", "question": "不要保存的秘密", "isSecret": true]
        ]
        send("item/tool/requestUserInput", base.merging(["isBlocking": false, "questions": questions]) { _, new in new }, id: "q1")
        guard reducer.threads["t1"]?.questions.first?.questions.count == 3,
              reducer.threads["t1"]?.blockingQuestions.isEmpty == true else { return false }
        send("item/tool/requestUserInput", base.merging(["isBlocking": true, "questions": questions]) { _, new in new }, id: "q2")
        guard reducer.threads["t1"]?.questions.count == 2,
              reducer.threads["t1"]?.blockingQuestions == Set(["s:q2"]) else { return false }
        send("serverRequest/resolved", ["threadId": "t1", "requestId": "q1"])
        guard reducer.threads["t1"]?.questions.count == 1 else { return false }
        reducer.removeQuestionText()
        guard reducer.threads["t1"]?.questions.isEmpty == true,
              reducer.threads["t1"]?.blockingQuestions.count == 1 else { return false }
        send("turn/completed", ["threadId": "t1", "turn": ["id": "turn1", "status": "interrupted"]])
        guard reducer.threads["t1"]?.blockingQuestions.isEmpty == true else { return false }
        guard CodexTaskProjection.merge(leases: [legacy], observations: reducer.snapshot(now: now).threads, now: now).isEmpty else { return false }
        send("turn/started", ["threadId": "t1", "turn": ["id": "turn2"]])
        send("item/tool/requestUserInput", base.merging(["isBlocking": true, "questions": questions]) { _, new in new }, id: "stale")
        guard reducer.threads["t1"]?.questions.isEmpty == true else { return false }
        send("item/tool/requestUserInput", ["threadId": "t1", "turnId": "turn2", "isBlocking": true, "questions": questions], id: "private", enabled: false)
        guard reducer.threads["t1"]?.questions.isEmpty == true,
              reducer.threads["t1"]?.blockingQuestions.count == 1 else { return false }
        return !String(decoding: try JSONEncoder().encode(reducer.snapshot(now: now)), as: UTF8.self).contains("秘密")
    }

    static func codexObservationFilesArePrivate() throws -> Bool {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blobfish-observer-check-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("snapshot.json")
        let thread = CodexObservedThread(id: "t1", turnID: "a", state: "running", timestamp: 1000)
        let data = try JSONEncoder().encode(CodexObservationSnapshot(timestamp: 1000, threads: [thread]))
        guard CodexObservationFiles.write(data, to: file), CodexObservationFiles.load(directory: root, now: 2000).count == 1,
              CodexObservationFiles.load(directory: root, now: 8000).isEmpty else { return false }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        guard CodexObservationFiles.load(directory: root, now: 2000).isEmpty else { return false }
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: root.appendingPathComponent("missing"))
        return CodexObservationFiles.load(directory: root, now: 2000).isEmpty && !CodexObservationFiles.questionsEnabled(settings: file)
    }

    @MainActor static func codexQuestionPaging() -> Bool {
        let model = CodexQuestionViewModel()
        let questions = ["一", "二", "三"].enumerated().map { CodexQuestion(id: String($0.offset), title: $0.element, options: []) }
        let request = CodexQuestionRequest(id: "one", threadID: "t1", turnID: "a", blocking: false, questions: questions)
        model.synchronize([request]); model.index = 2
        model.synchronize([request])
        guard model.index == 2, model.page?.question.title == "三" else { return false }
        model.synchronize([])
        return model.index == 0 && model.page == nil && AppConfig.defaults.integrations.codexQuestions == false
    }
}
