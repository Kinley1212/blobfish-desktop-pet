import Foundation
import Darwin

// Transparent transport: no fabricated RPC, no approvals, no response rewriting.
// Non app-server invocations exec the real CLI directly.
@main enum CodexObserver {
    static func main() {
        do { exit(try run()) }
        catch {
            // Transport errors must not generate Swift fatal-error crash reports
            // or include protocol contents in diagnostics.
            try? FileHandle.standardError.write(contentsOf: Data("Blobfish observer transport closed or unavailable.\n".utf8))
            exit(74)
        }
    }
    static func run() throws -> Int32 {
        let env = ProcessInfo.processInfo.environment
        let real = env["BLOBFISH_CODEX_REAL_CLI"] ?? "/Applications/ChatGPT.app/Contents/Resources/codex"
        guard real.hasPrefix("/"), real != CommandLine.arguments[0], FileManager.default.isExecutableFile(atPath: real) else { exit(126) }
        let arguments = Array(CommandLine.arguments.dropFirst())
        if !arguments.contains("app-server") {
            let args = ([real] + arguments).map { strdup($0) } + [nil]
            args.withUnsafeBufferPointer { _ = execv(real, $0.baseAddress!) }
            exit(126)
        }
        let directory = env["BLOBFISH_CODEX_OBSERVATION_DIR"].map { URL(fileURLWithPath: $0) } ?? CodexObservationFiles.directory
        let settings = env["BLOBFISH_SETTINGS"].map { URL(fileURLWithPath: $0) } ?? CodexObservationFiles.support.appendingPathComponent("settings.json")
        // The normal application support parent must already exist and be private.
        if CodexObservationFiles.secureDirectory(directory.deletingLastPathComponent()) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        let url = directory.appendingPathComponent("\(getpid())-\(UUID().uuidString.lowercased()).json")
        let lock = NSLock()
        var reducer = CodexObservationReducer()
        var includeQuestions = CodexObservationFiles.questionsEnabled(settings: settings)
        let writerQueue = DispatchQueue(label: "com.blobfish.codex-observer", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: writerQueue)
        timer.schedule(deadline: .now(), repeating: 2, leeway: .milliseconds(250))
        timer.setEventHandler {
            let enabled = CodexObservationFiles.questionsEnabled(settings: settings)
            lock.lock()
            includeQuestions = enabled
            if !enabled { reducer.removeQuestionText() }
            let snapshot = reducer.snapshot(now: Date().timeIntervalSince1970 * 1000)
            if let data = try? JSONEncoder().encode(snapshot) { _ = CodexObservationFiles.write(data, to: url) }
            lock.unlock()
        }
        timer.resume()
        defer {
            timer.cancel()
            writerQueue.sync { if CodexObservationFiles.secureDirectory(directory) { unlink(url.path) } }
        }

        let child = Process()
        child.executableURL = URL(fileURLWithPath: real)
        child.arguments = arguments
        var childEnvironment = env
        // Only our child uses the real binary; the desktop retains its observer override.
        childEnvironment["CODEX_CLI_PATH"] = real
        child.environment = childEnvironment
        child.standardInput = FileHandle.standardInput
        child.standardError = FileHandle.standardError
        let output = Pipe()
        child.standardOutput = output
        try child.run()
        // A closed desktop output pipe must unwind normally and terminate our
        // child, not kill the observer with SIGPIPE and leave a server behind.
        signal(SIGPIPE, SIG_IGN)
        defer { if child.isRunning { child.terminate() } }
        // Relay ordinary termination signals so the observer cannot orphan its server.
        signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
        let signals = [SIGTERM, SIGINT].map { number -> DispatchSourceSignal in
            let source = DispatchSource.makeSignalSource(signal: number, queue: writerQueue)
            source.setEventHandler { if child.isRunning { kill(child.processIdentifier, number) } }
            source.resume(); return source
        }
        defer { signals.forEach { $0.cancel() } }
        var line = Data()
        var droppingOversizedLine = false
        while true {
            let reachedEOF = try autoreleasepool {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { return true }
                chunk.withUnsafeBytes { bytes in
                    guard let base = bytes.baseAddress else { return }
                    var offset = 0
                    while offset < bytes.count {
                        // Scan native buffers in bulk instead of executing Swift
                        // collection operations for every byte of model output.
                        let newline = memchr(base.advanced(by: offset), 10, bytes.count - offset)
                        let end = newline.map { base.distance(to: $0) } ?? bytes.count
                        if !droppingOversizedLine {
                            if line.count + end - offset > 1024 * 1024 {
                                line.removeAll(keepingCapacity: true); droppingOversizedLine = true
                            } else {
                                line.append(base.advanced(by: offset).assumingMemoryBound(to: UInt8.self), count: end - offset)
                            }
                        }
                        if newline != nil {
                            if !droppingOversizedLine, let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                               let method = message["method"] as? String, CodexObservationReducer.observedMethods.contains(method) {
                                lock.lock()
                                let before = reducer.snapshot(now: 0)
                                reducer.receive(message, now: Date().timeIntervalSince1970 * 1000, includeQuestions: includeQuestions)
                                if before != reducer.snapshot(now: 0),
                                   let data = try? JSONEncoder().encode(reducer.snapshot(now: Date().timeIntervalSince1970 * 1000)) {
                                    _ = CodexObservationFiles.write(data, to: url)
                                }
                                lock.unlock()
                            }
                            line.removeAll(keepingCapacity: true); droppingOversizedLine = false
                        }
                        offset = end + (newline == nil ? 0 : 1)
                    }
                }
                // Original bytes, unchanged. Publish state changes promptly instead of
                // waiting for a heartbeat and showing a stale hook approval meanwhile.
                try FileHandle.standardOutput.write(contentsOf: chunk)
                return false
            }
            if reachedEOF { break }
        }
        child.waitUntilExit()
        return child.terminationReason == .exit ? child.terminationStatus : 128 + child.terminationStatus
    }
}
