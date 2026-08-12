import Darwin
import Foundation

struct CharacterPack: Equatable, Identifiable {
    struct Size: Codable, Equatable { let width: Double; let height: Double }
    struct Slot: Codable, Equatable { let x: Double; let y: Double; let scale: Double }
    struct Accessories: Codable, Equatable { let slots: [String: Slot] }
    struct Shape: Codable, Equatable {
        let id: String; let label: String; let d: String?; let left: String?; let right: String?; let hideShading: Bool?
    }
    struct DIY: Codable, Equatable { let enabled: Bool; let shapes: [String: [Shape]]? }
    struct Expressions: Codable, Equatable {
        let mode: String
        let defaultFaceID: String
        let moods: [String: String]

        private enum CodingKeys: String, CodingKey {
            case mode
            case defaultFaceID = "default"
            case moods
        }
    }
    struct Manifest: Codable, Equatable {
        let id: String
        let displayName: String
        let version: Int
        let renderer: String
        let art: String
        let preview: String?
        let size: Size
        let defaultLanguagePack: String?
        let accessories: Accessories?
        let diy: DIY?
        let expressions: Expressions?
    }

    let manifest: Manifest
    let directoryURL: URL
    var id: String { manifest.id }
    var artURL: URL { directoryURL.appendingPathComponent(manifest.art) }
}

struct AccessoryPack: Equatable, Identifiable {
    struct Point: Codable, Equatable { let x: Double; let y: Double }
    struct Manifest: Codable, Equatable {
        let id: String; let displayName: String; let version: Int; let slot: String
        let art: String; let anchor: Point; let hidesEyes: Bool?
        let characterPackIds: [String]?
        let nativeExpression: String?
    }
    let manifest: Manifest
    let directoryURL: URL
    var id: String { manifest.id }
    var artURL: URL { directoryURL.appendingPathComponent(manifest.art) }
}

struct LanguagePack: Equatable, Identifiable {
    struct Files: Codable, Equatable { let original: [String]; let additions: [String] }
    struct Manifest: Codable, Equatable {
        let id: String
        let displayName: String
        let locale: String
        let characterPackIds: [String]?
        let version: Int
        let files: Files
    }

    let manifest: Manifest
    let phrases: [Phrase]
    var id: String { manifest.id }
}

struct Phrase: Codable, Equatable, Identifiable {
    let id: String
    let event: String
    let text: String
    let weight: Double?
    let rarity: String?
    let cooldownMs: Double?
    let conditions: [String: JSONValue]?
}

struct DialoguePack: Codable, Equatable {
    struct Node: Codable, Equatable {
        let prompt: String
        let options: [Option]
        let opener: Bool?
    }

    struct Option: Codable, Equatable {
        let label: String
        let reply: String?
        let face: String?
        let next: String?
        let game: String?
    }

    let nodes: [String: Node]
}

private struct PhraseFile: Codable { let category: String; let phrases: [Phrase] }

enum PackCatalogError: Error, CustomStringConvertible {
    case missingRoot
    case unsafePath(String)
    case invalidManifest(String)
    case duplicate(String)

    var description: String {
        switch self {
        case .missingRoot: return "找不到内置资源包"
        case .unsafePath(let path): return "资源包路径不安全：\(path)"
        case .invalidManifest(let detail): return "资源包格式无效：\(detail)"
        case .duplicate(let id): return "资源包 id 重复：\(id)"
        }
    }
}

final class PackCatalog {
    static let maximumJSONBytes = 1024 * 1024
    static let maximumArtBytes = 2 * 1024 * 1024

    let packsRoot: URL

    init(packsRoot: URL = ResourceLocator.packsRoot()) throws {
        self.packsRoot = packsRoot
        guard Self.isDirectory(packsRoot) else { throw PackCatalogError.missingRoot }
    }

    func characters() throws -> [CharacterPack] {
        let root = packsRoot.appendingPathComponent("characters", isDirectory: true)
        return try loadDirectories(root: root) { directory in
            let manifest: CharacterPack.Manifest = try self.decodeJSON(directory.appendingPathComponent("manifest.json"))
            guard Self.isPackID(manifest.id), directory.lastPathComponent == manifest.id,
                  manifest.version == 1, manifest.renderer == "svg",
                  manifest.size.width > 0, manifest.size.height > 0,
                  Self.validExpressions(manifest.expressions) else {
                throw PackCatalogError.invalidManifest(directory.lastPathComponent)
            }
            let art = try self.safeChild(manifest.art, of: directory)
            try Self.requireRegularFile(art, maximumBytes: Self.maximumArtBytes)
            return CharacterPack(manifest: manifest, directoryURL: directory)
        }
    }

    func languages() throws -> [LanguagePack] {
        let root = packsRoot.appendingPathComponent("languages", isDirectory: true)
        return try loadDirectories(root: root) { directory in
            let manifest: LanguagePack.Manifest = try self.decodeJSON(directory.appendingPathComponent("manifest.json"))
            guard Self.isPackID(manifest.id), directory.lastPathComponent == manifest.id,
                  manifest.version == 1 else {
                throw PackCatalogError.invalidManifest(directory.lastPathComponent)
            }
            var phrases: [Phrase] = []
            var phraseIDs = Set<String>()
            for relativePath in manifest.files.original + manifest.files.additions {
                let fileURL = try self.safeChild(relativePath, of: directory)
                let file: PhraseFile = try self.decodeJSON(fileURL)
                for phrase in file.phrases {
                    guard !phrase.id.isEmpty, !phrase.event.isEmpty, !phrase.text.isEmpty,
                          phrase.id.utf8.count <= 128, phrase.text.utf8.count <= 2_000 else {
                        throw PackCatalogError.invalidManifest(relativePath)
                    }
                    guard phraseIDs.insert(phrase.id).inserted else { throw PackCatalogError.duplicate(phrase.id) }
                    phrases.append(phrase)
                }
            }
            return LanguagePack(manifest: manifest, phrases: phrases)
        }
    }

    func accessories() throws -> [AccessoryPack] {
        let root = packsRoot.appendingPathComponent("accessories", isDirectory: true)
        return try loadDirectories(root: root) { directory in
            let manifest: AccessoryPack.Manifest = try self.decodeJSON(directory.appendingPathComponent("manifest.json"))
            guard Self.isPackID(manifest.id), directory.lastPathComponent == manifest.id,
                  manifest.version == 1,
                  ["face", "hat", "eyewear", "hand", "clock", "message-indicator"].contains(manifest.slot),
                  Self.validCharacterPackIDs(manifest.characterPackIds),
                  Self.validNativeExpression(manifest) else {
                throw PackCatalogError.invalidManifest(directory.lastPathComponent)
            }
            let art = try self.safeChild(manifest.art, of: directory)
            try Self.requireRegularFile(art, maximumBytes: Self.maximumArtBytes)
            return AccessoryPack(manifest: manifest, directoryURL: directory)
        }
    }

    func character(id: String) throws -> CharacterPack {
        guard let pack = try characters().first(where: { $0.id == id }) else {
            throw PackCatalogError.invalidManifest("character \(id)")
        }
        return pack
    }

    func language(id: String) throws -> LanguagePack {
        guard let pack = try languages().first(where: { $0.id == id }) else {
            throw PackCatalogError.invalidManifest("language \(id)")
        }
        return pack
    }

    func dialogue(id: String) throws -> DialoguePack {
        guard Self.isPackID(id) else { throw PackCatalogError.invalidManifest("dialogue \(id)") }
        let root = packsRoot.appendingPathComponent("dialogues", isDirectory: true)
        let file = try safeChild("\(id).json", of: root)
        let pack: DialoguePack = try decodeJSON(file)
        let nodeIDs = Set(pack.nodes.keys)
        guard (1...200).contains(pack.nodes.count),
              pack.nodes.values.contains(where: { $0.opener == true }) else {
            throw PackCatalogError.invalidManifest("dialogue \(id)")
        }
        for (nodeID, node) in pack.nodes {
            guard Self.isPackID(nodeID), !node.prompt.isEmpty, node.prompt.count <= 140,
                  (1...4).contains(node.options.count) else {
                throw PackCatalogError.invalidManifest("dialogue node \(nodeID)")
            }
            for option in node.options {
                guard !option.label.isEmpty, option.label.count <= 30,
                      option.reply.map({ $0.count <= 200 }) ?? true,
                      option.face.map({ $0.range(of: #"^face-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$"#, options: .regularExpression) != nil }) ?? true,
                      option.next.map(nodeIDs.contains) ?? true,
                      option.game.map({ ["rps", "dice", "riddle"].contains($0) }) ?? true else {
                    throw PackCatalogError.invalidManifest("dialogue node \(nodeID) option")
                }
            }
        }
        return pack
    }

    private func loadDirectories<T>(root: URL, transform: (URL) throws -> T) throws -> [T] {
        guard Self.isDirectory(root) else { return [] }
        let directories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).filter { Self.isDirectory($0) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try directories.map(transform)
    }

    private func decodeJSON<T: Decodable>(_ url: URL) throws -> T {
        try Self.requireRegularFile(url, maximumBytes: Self.maximumJSONBytes)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func safeChild(_ relativePath: String, of directory: URL) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains("\\"),
              relativePath.split(separator: "/").allSatisfy({ $0 != ".." && $0 != "." }) else {
            throw PackCatalogError.unsafePath(relativePath)
        }
        let root = directory.standardizedFileURL.path + "/"
        let child = directory.appendingPathComponent(relativePath).standardizedFileURL
        guard child.path.hasPrefix(root) else { throw PackCatalogError.unsafePath(relativePath) }
        return child
    }

    private static func requireRegularFile(_ url: URL, maximumBytes: Int) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= maximumBytes else {
            throw PackCatalogError.unsafePath(url.lastPathComponent)
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    private static func isPackID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$"#, options: .regularExpression) != nil
    }

    private static func validExpressions(_ expressions: CharacterPack.Expressions?) -> Bool {
        guard let expressions else { return true }
        guard expressions.mode == "native",
              isPackID(expressions.defaultFaceID),
              !expressions.moods.isEmpty,
              expressions.moods.keys.allSatisfy(isPackID),
              expressions.moods.values.allSatisfy(isPackID) else { return false }
        return expressions.moods.values.contains(expressions.defaultFaceID)
    }

    private static func validNativeExpression(_ manifest: AccessoryPack.Manifest) -> Bool {
        guard let nativeExpression = manifest.nativeExpression else { return true }
        return manifest.slot == "face"
            && isPackID(nativeExpression)
            && !(manifest.characterPackIds?.isEmpty ?? true)
            && manifest.hidesEyes != true
    }

    private static func validCharacterPackIDs(_ ids: [String]?) -> Bool {
        guard let ids else { return true }
        return !ids.isEmpty && ids.allSatisfy(isPackID) && Set(ids).count == ids.count
    }
}

enum CharacterExpressionCompatibility {
    static func isCompatible(_ accessory: AccessoryPack, with character: CharacterPack) -> Bool {
        if let characterPackIds = accessory.manifest.characterPackIds,
           !characterPackIds.contains(character.id) {
            return false
        }
        guard accessory.manifest.slot == "face" else { return true }
        if let expressions = character.manifest.expressions, expressions.mode == "native" {
            return accessory.manifest.nativeExpression != nil
                && expressions.moods.values.contains(accessory.id)
        }
        return accessory.manifest.nativeExpression == nil
    }

    static func accessories(
        _ accessories: [AccessoryPack], compatibleWith character: CharacterPack?, slot: String? = nil
    ) -> [AccessoryPack] {
        accessories.filter { accessory in
            (slot == nil || accessory.manifest.slot == slot)
                && character.map { isCompatible(accessory, with: $0) } != false
        }
    }

    static func resolveFaceID(
        _ requestedFaceID: String?, for character: CharacterPack?, accessories: [AccessoryPack]
    ) -> String? {
        guard let character else { return nil }
        let compatibleFaces = self.accessories(accessories, compatibleWith: character, slot: "face")
        if let requestedFaceID,
           compatibleFaces.contains(where: { $0.id == requestedFaceID }) {
            return requestedFaceID
        }
        guard let requestedFaceID,
              let expressions = character.manifest.expressions,
              expressions.mode == "native",
              let mood = semanticMood(for: requestedFaceID) else { return nil }
        let mapped = expressions.moods[mood] ?? expressions.defaultFaceID
        return compatibleFaces.contains(where: { $0.id == mapped }) ? mapped : nil
    }

    static func nativeExpression(
        for requestedFaceID: String?, character: CharacterPack?, accessories: [AccessoryPack]
    ) -> String? {
        guard let character,
              let expressions = character.manifest.expressions,
              expressions.mode == "native" else { return nil }
        let resolved = resolveFaceID(requestedFaceID, for: character, accessories: accessories)
            ?? expressions.defaultFaceID
        return accessories.first(where: {
            $0.id == resolved && isCompatible($0, with: character)
        })?.manifest.nativeExpression
    }

    static func portableFaceID(
        _ faceID: String?, for character: CharacterPack?, accessories: [AccessoryPack]
    ) -> String? {
        guard let faceID, !faceID.isEmpty else { return nil }
        guard let character,
              let expressions = character.manifest.expressions,
              expressions.mode == "native",
              let nativeExpression = nativeExpression(
                  for: faceID, character: character, accessories: accessories
              ) else { return faceID }
        switch nativeExpression {
        case "happy": return "face-happy"
        case "worried": return "face-pitiful"
        case "calm": return "face-blank"
        default: return expressions.defaultFaceID
        }
    }

    private static func semanticMood(for faceID: String) -> String? {
        if positiveFaceIDs.contains(faceID) { return "happy" }
        if worriedFaceIDs.contains(faceID) { return "worried" }
        if calmFaceIDs.contains(faceID) { return "calm" }
        return nil
    }

    private static let positiveFaceIDs: Set<String> = [
        "face-coy", "face-happy", "face-love", "face-money", "face-nosebleed",
        "face-proud", "face-relieved", "face-satisfied", "face-shy", "face-smug",
        "face-sparkle", "face-star-eye", "face-swirl-cheek", "face-teasing", "face-wink",
    ]
    private static let worriedFaceIDs: Set<String> = [
        "face-angry", "face-annoyed", "face-cold", "face-cry", "face-dizzy", "face-doubt",
        "face-hungry", "face-panic", "face-pitiful", "face-question", "face-scared", "face-shocked",
    ]
    private static let calmFaceIDs: Set<String> = [
        "face-blank", "face-determined", "face-side-eye", "face-sleepy",
    ]
}

enum ResourceLocator {
    static func packsRoot() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["BLOBFISH_PACKS_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("packs", isDirectory: true),
           FileManager.default.fileExists(atPath: resource.path) {
            return resource
        }
        var cursor = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for _ in 0..<5 {
            let candidate = cursor.appendingPathComponent("src/packs", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            cursor.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: "/nonexistent/blobfish-packs", isDirectory: true)
    }
}
