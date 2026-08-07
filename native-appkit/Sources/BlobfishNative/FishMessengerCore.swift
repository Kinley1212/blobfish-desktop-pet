import CryptoKit
import Foundation

enum FishMessengerError: Error, Equatable, LocalizedError {
    case invalidInvite
    case invalidMessage
    case unsupportedVersion
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .invalidInvite: return "The fish code or contact is invalid."
        case .invalidMessage: return "The fish message is empty or too long."
        case .unsupportedVersion: return "This fish message version is not supported."
        case .decryptionFailed: return "The fish message failed authentication."
        }
    }
}

struct FishInvite: Codable, Equatable {
    static let version = 1

    let version: Int
    let relayURL: URL
    let inboxID: String
    let deliveryToken: String
    let publicKey: String
    let displayName: String

    init(relayURL: URL, inboxID: String, deliveryToken: String, publicKey: String, displayName: String) throws {
        self.version = Self.version
        self.relayURL = relayURL
        self.inboxID = inboxID
        self.deliveryToken = deliveryToken
        self.publicKey = publicKey
        self.displayName = displayName
        try validate()
    }

    func encoded() throws -> String {
        try validate()
        return "fish1_" + Self.base64URL(try JSONEncoder().encode(self))
    }

    static func decode(_ value: String) throws -> FishInvite {
        guard value.hasPrefix("fish1_"),
              let data = dataFromBase64URL(String(value.dropFirst(6))),
              data.count <= 4_096,
              let invite = try? JSONDecoder().decode(FishInvite.self, from: data) else {
            throw FishMessengerError.invalidInvite
        }
        try invite.validate()
        return invite
    }

    private func validate() throws {
        guard version == Self.version else { throw FishMessengerError.unsupportedVersion }
        guard relayURL.scheme == "https", relayURL.host != nil, relayURL.user == nil, relayURL.password == nil,
              relayURL.query == nil, relayURL.fragment == nil,
              Self.isToken(inboxID, range: 16...128),
              Self.isToken(deliveryToken, range: 32...256),
              displayName.utf8.count <= 48,
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !displayName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let keyData = Data(base64Encoded: publicKey), keyData.count == 32,
              (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: keyData)) != nil else {
            throw FishMessengerError.invalidInvite
        }
    }

    private static func isToken(_ value: String, range: ClosedRange<Int>) -> Bool {
        range.contains(value.utf8.count)
            && value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    fileprivate static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    fileprivate static func dataFromBase64URL(_ value: String) -> Data? {
        guard value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { return nil }
        let padding = String(repeating: "=", count: (4 - value.count % 4) % 4)
        return Data(base64Encoded: value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/") + padding)
    }
}

struct FishMessage: Codable, Equatable {
    static let maximumTextBytes = 1_000

    let id: UUID
    let sentAt: Date
    let senderName: String
    let text: String
    let replyTo: UUID?
    let kind: FishMessageKind?
    let bubbleColor: String?
    let presence: FishPresence?
    let receipt: FishDeliveryReceipt?
    let interaction: FishRemoteInteraction?

    init(
        id: UUID = UUID(), sentAt: Date = Date(), senderName: String, text: String,
        replyTo: UUID? = nil, kind: FishMessageKind? = nil,
        bubbleColor: String? = nil, presence: FishPresence? = nil,
        receipt: FishDeliveryReceipt? = nil, interaction: FishRemoteInteraction? = nil
    ) throws {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.utf8.count <= Self.maximumTextBytes,
              senderName.utf8.count <= 48,
              !senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !senderName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw FishMessengerError.invalidMessage
        }
        self.id = id
        self.sentAt = sentAt
        self.senderName = senderName
        self.text = normalized
        self.replyTo = replyTo
        self.kind = kind
        self.bubbleColor = bubbleColor
        self.presence = presence
        self.receipt = receipt
        self.interaction = interaction
    }
}

struct FishEncryptedEnvelope: Codable, Equatable {
    let version: Int
    let senderPublicKey: String
    let ciphertext: String
}

struct FishMessengerIdentity {
    private let privateKey: Curve25519.KeyAgreement.PrivateKey

    init() { privateKey = Curve25519.KeyAgreement.PrivateKey() }

    init(rawPrivateKey: Data) throws {
        privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: rawPrivateKey)
    }

    var rawPrivateKey: Data { privateKey.rawRepresentation }
    var publicKey: String { privateKey.publicKey.rawRepresentation.base64EncodedString() }

    func encrypt(_ message: FishMessage, for recipientPublicKey: String) throws -> FishEncryptedEnvelope {
        guard let recipientData = Data(base64Encoded: recipientPublicKey),
              let recipient = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientData) else {
            throw FishMessengerError.invalidInvite
        }
        let key = try symmetricKey(peer: recipient)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let sealed = try ChaChaPoly.seal(encoder.encode(message), using: key)
        return FishEncryptedEnvelope(
            version: 1,
            senderPublicKey: publicKey,
            ciphertext: sealed.combined.base64EncodedString()
        )
    }

    func decrypt(_ envelope: FishEncryptedEnvelope, expectedSenderPublicKey: String) throws -> FishMessage {
        guard envelope.version == 1 else { throw FishMessengerError.unsupportedVersion }
        guard envelope.senderPublicKey == expectedSenderPublicKey,
              let senderData = Data(base64Encoded: envelope.senderPublicKey),
              let sender = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderData),
              let combined = Data(base64Encoded: envelope.ciphertext),
              combined.count <= 4_096,
              let box = try? ChaChaPoly.SealedBox(combined: combined) else {
            throw FishMessengerError.decryptionFailed
        }
        do {
            let plaintext = try ChaChaPoly.open(box, using: try symmetricKey(peer: sender))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let decoded = try decoder.decode(FishMessage.self, from: plaintext)
            return try FishMessage(
                id: decoded.id,
                sentAt: decoded.sentAt,
                senderName: decoded.senderName,
                text: decoded.text,
                replyTo: decoded.replyTo,
                kind: decoded.kind,
                bubbleColor: decoded.bubbleColor,
                presence: decoded.presence,
                receipt: decoded.receipt,
                interaction: decoded.interaction
            )
        } catch {
            throw FishMessengerError.decryptionFailed
        }
    }

    private func symmetricKey(peer: Curve25519.KeyAgreement.PublicKey) throws -> SymmetricKey {
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        let publicKeys = [privateKey.publicKey.rawRepresentation, peer.rawRepresentation].sorted { $0.lexicographicallyPrecedes($1) }
        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("blobfish-fish-messenger-v1".utf8),
            sharedInfo: publicKeys[0] + publicKeys[1],
            outputByteCount: 32
        )
    }
}
