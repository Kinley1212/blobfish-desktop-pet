import AppKit
import CryptoKit
import Foundation

struct NativeUpdateManifest: Decodable, Equatable {
    struct Asset: Decodable, Equatable { let name: String; let size: Int; let digest: String; let url: String }
    let channel: String
    let version: String
    let repository: String
    let assets: [String: Asset]
}

enum NativeUpdateResult: Equatable { case upToDate(String); case available(NativeUpdateManifest, NativeUpdateManifest.Asset) }

final class NativeUpdater {
    static let repository = "Kinley1212/blobfish-desktop-pet"
    static let manifestURL = URL(string: "https://github.com/\(repository)/releases/latest/download/blobfish-native-latest.json")!
    static let maximumAssetBytes = 256 * 1024 * 1024

    private let session: URLSession
    let currentVersion: String

    init(session: URLSession = .shared) {
        self.session = session
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    func check(completion: @escaping (Result<NativeUpdateResult, Error>) -> Void) {
        var request = URLRequest(url: Self.manifestURL, timeoutInterval: 20)
        request.setValue("BlobfishNative/\(currentVersion) (macOS updater)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { data, response, error in
            let result: Result<NativeUpdateResult, Error>
            do {
                if let error { throw error }
                guard let http = response as? HTTPURLResponse else { throw UpdaterError.invalidResponse }
                if http.statusCode == 404 { throw UpdaterError.channelNotPublished }
                guard http.statusCode == 200, let data, data.count <= 1024 * 1024 else { throw UpdaterError.http(http.statusCode) }
                let manifest = try JSONDecoder().decode(NativeUpdateManifest.self, from: data)
                result = .success(try Self.select(manifest: manifest, currentVersion: self.currentVersion, architecture: Self.architecture))
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    func install(manifest: NativeUpdateManifest, asset: NativeUpdateManifest.Asset, progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let url = URL(string: asset.url) else { completion(.failure(UpdaterError.invalidAsset)); return }
        var request = URLRequest(url: url, timeoutInterval: 180)
        request.setValue("BlobfishNative/\(currentVersion) (macOS updater)", forHTTPHeaderField: "User-Agent")
        progress(0.05)
        session.downloadTask(with: request) { location, response, error in
            do {
                if let error { throw error }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let location else { throw UpdaterError.invalidDownload }
                let values = try location.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      values.fileSize == asset.size, asset.size <= Self.maximumAssetBytes else { throw UpdaterError.invalidDownload }
                let digest = try Self.sha256(of: location)
                guard asset.digest.lowercased() == "sha256:\(digest)" else { throw UpdaterError.digestMismatch }
                DispatchQueue.main.async { progress(0.65) }
                let installed = try Self.stageAndInstall(zipURL: location, version: manifest.version)
                DispatchQueue.main.async { progress(1); completion(.success(installed)) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }.resume()
    }

    func relaunch(at applicationURL: URL, completion: @escaping (Error?) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, error in completion(error) }
    }

    private static func stageAndInstall(zipURL: URL, version: String) throws -> URL {
        let updates = FileManager.default.temporaryDirectory.appendingPathComponent("blobfish-native-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: updates, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: updates) }
        let zip = updates.appendingPathComponent("update.zip")
        try FileManager.default.copyItem(at: zipURL, to: zip)
        let expanded = updates.appendingPathComponent("expanded", isDirectory: true)
        try FileManager.default.createDirectory(at: expanded, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", "--sequesterRsrc", "--rsrc", zip.path, expanded.path]
        process.standardOutput = Pipe(); process.standardError = Pipe(); try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdaterError.extractFailed }
        let candidates = try FileManager.default.contentsOfDirectory(at: expanded, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.pathExtension == "app" }
        guard candidates.count == 1, let bundle = Bundle(url: candidates[0]),
              bundle.bundleIdentifier == "com.blobfish.desktop-pet.native",
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version else {
            throw UpdaterError.invalidBundle
        }
        let verification = Process(); verification.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verification.arguments = ["--verify", "--deep", "--strict", candidates[0].path]
        verification.standardOutput = Pipe(); verification.standardError = Pipe(); try verification.run(); verification.waitUntilExit()
        guard verification.terminationStatus == 0 else { throw UpdaterError.invalidBundle }
        let currentBundle = Bundle.main.bundleURL
        let preferredDirectory = currentBundle.pathExtension == "app" ? currentBundle.deletingLastPathComponent() : URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
        let installDirectory: URL
        if FileManager.default.isWritableFile(atPath: preferredDirectory.path) { installDirectory = preferredDirectory }
        else {
            installDirectory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true)
            try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        }
        return try installVerifiedBundle(
            at: candidates[0],
            in: installDirectory,
            currentBundle: currentBundle
        )
    }

    static func installVerifiedBundle(
        at candidate: URL,
        in installDirectory: URL,
        currentBundle: URL,
        replace: (URL, URL, URL) throws -> Void = { target, temporary, backup in
            try RecoverableDirectoryInstaller.replace(target: target, with: temporary, backup: backup)
        }
    ) throws -> URL {
        let target = installDirectory.appendingPathComponent("水滴鱼.app", isDirectory: true)
        let temporary = installDirectory.appendingPathComponent(".水滴鱼-installing-\(UUID().uuidString).app", isDirectory: true)
        let backup = installDirectory.appendingPathComponent(".水滴鱼-backup-\(UUID().uuidString).app", isDirectory: true)
        try FileManager.default.copyItem(at: candidate, to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try replace(target, temporary, backup)
        if currentBundle != target,
           currentBundle.pathExtension == "app",
           currentBundle.deletingLastPathComponent() == installDirectory {
            try? FileManager.default.removeItem(at: currentBundle)
        }
        return target
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static var architecture: String {
#if arch(arm64)
        "arm64"
#else
        "x64"
#endif
    }

    static func select(manifest: NativeUpdateManifest, currentVersion: String, architecture: String) throws -> NativeUpdateResult {
        try validate(manifest)
        guard let comparison = compareVersions(manifest.version, currentVersion) else {
            throw UpdaterError.invalidCurrentVersion(currentVersion)
        }
        guard comparison > 0 else { return .upToDate(currentVersion) }
        guard let asset = manifest.assets[architecture] else { throw UpdaterError.noAsset(architecture) }
        try validate(asset: asset, version: manifest.version, architecture: architecture)
        return .available(manifest, asset)
    }

    private static func validate(_ manifest: NativeUpdateManifest) throws {
        guard manifest.channel == "native-appkit", manifest.repository == repository,
              parseVersion(manifest.version) != nil else { throw UpdaterError.invalidManifest }
    }

    private static func validate(asset: NativeUpdateManifest.Asset, version: String, architecture: String) throws {
        guard asset.name == "BlobfishNative-\(version)-macOS-\(architecture).zip",
              asset.size > 0, asset.size <= maximumAssetBytes,
              asset.digest.range(of: #"^sha256:[a-f0-9]{64}$"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let url = URL(string: asset.url), url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/\(repository)/releases/") else { throw UpdaterError.invalidAsset }
    }

    private struct SemanticVersion {
        let core: [Int]
        let prerelease: [String]?
    }

    private static func parseVersion(_ value: String) -> SemanticVersion? {
        let withoutBuild = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard let version = withoutBuild.first, !version.isEmpty else { return nil }
        let parts = version.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let coreStrings = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard coreStrings.count == 3,
              coreStrings.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(coreStrings[0]),
              let minor = Int(coreStrings[1]),
              let patch = Int(coreStrings[2]) else { return nil }
        var prerelease: [String]?
        if parts.count == 2 {
            let identifiers = parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
            guard !identifiers.isEmpty,
                  identifiers.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }) else {
                return nil
            }
            prerelease = identifiers
        }
        return SemanticVersion(core: [major, minor, patch], prerelease: prerelease)
    }

    static func compareVersions(_ left: String, _ right: String) -> Int? {
        guard let lhs = parseVersion(left), let rhs = parseVersion(right) else { return nil }
        for index in 0..<3 where lhs.core[index] != rhs.core[index] {
            return lhs.core[index] < rhs.core[index] ? -1 : 1
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return 0
        case (nil, _?): return 1
        case (_?, nil): return -1
        case (.some(let leftIdentifiers), .some(let rightIdentifiers)):
            for index in 0..<max(leftIdentifiers.count, rightIdentifiers.count) {
                guard index < leftIdentifiers.count else { return -1 }
                guard index < rightIdentifiers.count else { return 1 }
                let left = leftIdentifiers[index]
                let right = rightIdentifiers[index]
                if left == right { continue }
                switch (Int(left), Int(right)) {
                case (.some(let leftNumber), .some(let rightNumber)):
                    return leftNumber < rightNumber ? -1 : 1
                case (.some, .none): return -1
                case (.none, .some): return 1
                case (.none, .none): return left < right ? -1 : 1
                }
            }
        }
        return 0
    }
}

enum UpdaterError: Error, LocalizedError {
    case channelNotPublished, invalidResponse, http(Int), invalidManifest, invalidCurrentVersion(String), noAsset(String), invalidAsset
    case invalidDownload, digestMismatch, extractFailed, invalidBundle
    var errorDescription: String? {
        switch self {
        case .channelNotPublished: return "原生版更新渠道尚未发布；当前是开发预览版"
        case .invalidResponse: return "GitHub 返回了无效响应"
        case .http(let code): return "GitHub 返回了 \(code)"
        case .invalidManifest: return "原生版更新清单无效"
        case .invalidCurrentVersion(let version): return "当前版本号无法比较：\(version)"
        case .noAsset(let architecture): return "没有适用于 \(architecture) Mac 的原生安装包"
        case .invalidAsset: return "原生安装包信息无效"
        case .invalidDownload: return "下载的安装包大小不符"
        case .digestMismatch: return "安装包 SHA-256 校验失败"
        case .extractFailed: return "无法解压原生安装包"
        case .invalidBundle: return "安装包中的应用身份或版本不符"
        }
    }
}
