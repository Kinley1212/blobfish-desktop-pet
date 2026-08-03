import Foundation

struct IntegrationStatus: Equatable {
    let provider: String
    let cliFound: Bool
    let installed: Bool
    let verified: Bool
    let detail: String
}

final class IntegrationManager {
    private let supportDirectory: URL
    private let resourcesRoot: URL
    private let queue = DispatchQueue(label: "com.blobfish.native.integrations", qos: .userInitiated)

    init(supportDirectory: URL) {
        self.supportDirectory = supportDirectory
        if let bundleRoot = Bundle.main.resourceURL?.appendingPathComponent("integrations"),
           FileManager.default.fileExists(atPath: bundleRoot.path) {
            resourcesRoot = bundleRoot
        } else {
            var cursor = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            var found: URL?
            for _ in 0..<5 {
                let candidate = cursor.appendingPathComponent("integrations", isDirectory: true)
                if FileManager.default.fileExists(atPath: candidate.path) { found = candidate; break }
                cursor.deleteLastPathComponent()
            }
            resourcesRoot = found ?? URL(fileURLWithPath: "/nonexistent/blobfish-integrations")
        }
    }

    func inspect(_ provider: String, completion: @escaping (IntegrationStatus) -> Void) {
        queue.async { [weak self] in
            let result = self?.inspectSynchronously(provider) ?? IntegrationStatus(
                provider: provider, cliFound: false, installed: false, verified: false, detail: "连接管理器不可用"
            )
            DispatchQueue.main.async { completion(result) }
        }
    }

    func connect(_ provider: String, completion: @escaping (Result<IntegrationStatus, Error>) -> Void) {
        queue.async { [weak self] in
            do {
                guard let self else { throw IntegrationError.invalidProvider }
                let definition = try Definition(provider: provider)
                guard let cli = self.findExecutable(definition.cli) else { throw IntegrationError.cliMissing(definition.cli) }
                let target = try self.prepare(definition)
                let marketplaceList = try self.run(cli, arguments: definition.marketplaceList)
                if !marketplaceList.contains("blobfish-pet") {
                    _ = try self.run(cli, arguments: definition.marketplaceAdd(target.path))
                }
                let pluginList = try self.run(cli, arguments: definition.pluginList)
                if !pluginList.contains("blobfish-agent-bridge") {
                    _ = try self.run(cli, arguments: definition.pluginAdd)
                }
                let status = self.inspectSynchronously(provider)
                guard status.installed else { throw IntegrationError.installFailed }
                DispatchQueue.main.async { completion(.success(status)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func inspectSynchronously(_ provider: String) -> IntegrationStatus {
        guard let definition = try? Definition(provider: provider) else {
            return .init(provider: provider, cliFound: false, installed: false, verified: false, detail: "不支持的连接")
        }
        guard let cli = findExecutable(definition.cli) else {
            return .init(provider: provider, cliFound: false, installed: false, verified: false, detail: "未找到 \(definition.cli) 命令行工具")
        }
        do {
            let output = try run(cli, arguments: definition.pluginList)
            let installed = output.contains("blobfish-agent-bridge")
            let verified = hasRecentLease(provider: definition.leaseProvider)
            let detail: String
            if verified { detail = "已连接，并收到过真实任务状态" }
            else if installed, provider == "codex" { detail = "已安装；请在 Codex 的 /hooks 允许水滴鱼，然后继续一次任务" }
            else if installed { detail = "已安装；重新打开 Claude Code 会话后继续一次任务" }
            else { detail = "尚未安装状态插件" }
            return .init(provider: provider, cliFound: true, installed: installed, verified: verified, detail: detail)
        } catch {
            return .init(provider: provider, cliFound: true, installed: false, verified: false, detail: "检查失败：\(error.localizedDescription)")
        }
    }

    private func prepare(_ definition: Definition) throws -> URL {
        let source = resourcesRoot.appendingPathComponent(definition.resourceDirectory, isDirectory: true)
        guard FileManager.default.fileExists(atPath: source.path) else { throw IntegrationError.resourcesMissing }
        let managedRoot = supportDirectory.appendingPathComponent("managed-integrations", isDirectory: true)
        let target = managedRoot.appendingPathComponent(definition.resourceDirectory, isDirectory: true)
        let temporary = managedRoot.appendingPathComponent(".\(definition.resourceDirectory)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: managedRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.copyItem(at: source, to: temporary)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: temporary, to: target)

        let senderSource = Bundle.main.resourceURL?.appendingPathComponent("native/blobfish-agent-event-sender")
            ?? URL(fileURLWithPath: "/nonexistent/blobfish-agent-event-sender")
        guard FileManager.default.isExecutableFile(atPath: senderSource.path) else { throw IntegrationError.senderMissing }
        let pluginRoot = definition.provider == "codex"
            ? target.appendingPathComponent("plugins/blobfish-agent-bridge", isDirectory: true)
            : target.appendingPathComponent("blobfish-agent-bridge", isDirectory: true)
        let bin = pluginRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let senderTarget = bin.appendingPathComponent("blobfish-agent-event-sender")
        try FileManager.default.copyItem(at: senderSource, to: senderTarget)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: senderTarget.path)
        return target
    }

    private func run(_ executable: URL, arguments: [String]) throws -> String {
        let process = Process(); process.executableURL = executable; process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["CI"] = "1"; environment["NO_COLOR"] = "1"; environment["TERM"] = "dumb"
        process.environment = environment
        let output = Pipe(), errors = Pipe(); process.standardOutput = output; process.standardError = errors
        try process.run(); process.waitUntilExit()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let detail = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw IntegrationError.commandFailed(String((detail ?? "连接命令失败").suffix(600)))
        }
        return String(data: stdout, encoding: .utf8) ?? ""
    }

    private func findExecutable(_ name: String) -> URL? {
        var candidates = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)).appendingPathComponent(name) }
        candidates += ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin"].map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
        let nvm = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(at: nvm, includingPropertiesForKeys: nil) {
            candidates += versions.map { $0.appendingPathComponent("bin/\(name)") }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func hasRecentLease(provider: String) -> Bool {
        let directory = supportDirectory.appendingPathComponent("agent-task-leases", isDirectory: true)
        guard let leases = try? TaskLeaseReader(directoryURL: directory).read() else { return false }
        return leases.contains { $0.provider == provider }
    }
}

private struct Definition {
    let provider: String
    let cli: String
    let resourceDirectory: String
    let leaseProvider: String
    let pluginList: [String]
    let marketplaceList: [String]
    let pluginAdd: [String]
    let marketplaceAdd: (String) -> [String]

    init(provider: String) throws {
        self.provider = provider
        if provider == "codex" {
            cli = "codex"; resourceDirectory = "codex"; leaseProvider = "codex"
            pluginList = ["plugin", "list", "--json"]
            marketplaceList = ["plugin", "marketplace", "list", "--json"]
            pluginAdd = ["plugin", "add", "blobfish-agent-bridge@blobfish-pet", "--json"]
            marketplaceAdd = { ["plugin", "marketplace", "add", $0, "--json"] }
        } else if provider == "claude" {
            cli = "claude"; resourceDirectory = "claude-code"; leaseProvider = "claude-code"
            pluginList = ["plugin", "list", "--json"]
            marketplaceList = ["plugin", "marketplace", "list", "--json"]
            pluginAdd = ["plugin", "install", "blobfish-agent-bridge@blobfish-pet", "--scope", "user"]
            marketplaceAdd = { ["plugin", "marketplace", "add", $0, "--scope", "user"] }
        } else { throw IntegrationError.invalidProvider }
    }
}

private enum IntegrationError: Error, LocalizedError {
    case invalidProvider, resourcesMissing, senderMissing, cliMissing(String), installFailed, commandFailed(String)
    var errorDescription: String? {
        switch self {
        case .invalidProvider: return "不支持的连接类型"
        case .resourcesMissing: return "内置连接插件不完整"
        case .senderMissing: return "任务状态发送器缺失"
        case .cliMissing(let name): return "未找到 \(name) 命令行工具"
        case .installFailed: return "插件安装后仍未启用"
        case .commandFailed(let detail): return detail
        }
    }
}
