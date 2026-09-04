import Darwin
import Foundation

enum BoundedProcessRunnerError: Error, Equatable {
    case timedOut
    case outputUnavailable
}

struct BoundedProcessResult: Equatable {
    let terminationStatus: Int32
    let standardOutput: Data
}

enum BoundedProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        captureStandardOutput: Bool = false,
        environment: [String: String]? = nil
    ) throws -> BoundedProcessResult {
        precondition(timeout > 0)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment

        let output = captureStandardOutput ? Pipe() : nil
        process.standardOutput = output ?? FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }

        let captured = LockedProcessOutput()
        let readerFinished = DispatchSemaphore(value: 0)
        try process.run()
        if let output {
            DispatchQueue.global(qos: .utility).async {
                captured.set(output.fileHandleForReading.readDataToEndOfFile())
                readerFinished.signal()
            }
        }

        guard terminated.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            if terminated.wait(timeout: .now() + 1) != .success {
                kill(process.processIdentifier, SIGKILL)
                _ = terminated.wait(timeout: .now() + 1)
            }
            output?.fileHandleForReading.closeFile()
            throw BoundedProcessRunnerError.timedOut
        }

        if output != nil, readerFinished.wait(timeout: .now() + 2) != .success {
            output?.fileHandleForReading.closeFile()
            throw BoundedProcessRunnerError.outputUnavailable
        }
        return BoundedProcessResult(
            terminationStatus: process.terminationStatus,
            standardOutput: captured.value
        )
    }
}

private final class LockedProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func set(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }
}
