import Foundation
import XCTest
@testable import BlobfishNative

final class TaskLeaseReaderTests: XCTestCase {
    func testReadsPrivateBoundedLeaseAndBuildsRunningSnapshot() throws {
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
            XCTAssertEqual(leases.count, 1)
            XCTAssertEqual(leases[0].title, "修复原生桌宠")
            XCTAssertEqual(TaskSnapshot.build(from: leases, nowMilliseconds: now), TaskSnapshot(
                state: .running,
                title: "修复原生桌宠",
                activeCount: 1
            ))
        }
    }

    func testWaitingTasksUseWaitingStateAndProviderFallbackTitle() throws {
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
            XCTAssertEqual(TaskSnapshot.build(from: leases, nowMilliseconds: now), TaskSnapshot(
                state: .waiting,
                title: "Claude Code 任务",
                activeCount: 1
            ))
        }
    }

    func testTerminalStatusIsBriefAndThenReturnsToIdle() throws {
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
        XCTAssertEqual(
            TaskSnapshot.build(from: [lease], nowMilliseconds: 14_000).state,
            .completed
        )
        XCTAssertEqual(
            TaskSnapshot.build(from: [lease], nowMilliseconds: 16_000),
            .idle
        )
    }

    func testRejectsInsecureDirectoryAndIgnoresSymlinksOrOversizedFiles() throws {
        try withPrivateDirectory { directory in
            let target = directory.appendingPathComponent("target.json")
            try Data("{}".utf8).write(to: target)
            let symlink = directory.appendingPathComponent(String(repeating: "c", count: 64) + ".json")
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)

            let oversized = directory.appendingPathComponent(String(repeating: "d", count: 64) + ".json")
            try Data(repeating: 1, count: TaskLeaseReader.maximumFileBytes + 1).write(to: oversized)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: oversized.path)
            XCTAssertEqual(try TaskLeaseReader(directoryURL: directory).read(), [])

            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            XCTAssertThrowsError(try TaskLeaseReader(directoryURL: directory).read())
        }
    }

    private func withPrivateDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blobfish-native-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func writeLease(_ object: [String: Any], named name: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(name)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
