import Foundation
import Security

struct FishContact: Codable, Equatable, Identifiable {
    let id: UUID
    var invite: FishInvite
    var muted: Bool
    var blocked: Bool
    var nickname: String?
    var lastPresence: FishPresence?

    init(id: UUID = UUID(), invite: FishInvite, muted: Bool = false, blocked: Bool = false) {
        self.id = id
        self.invite = invite
        self.muted = muted
        self.blocked = blocked
        self.nickname = nil
        self.lastPresence = nil
    }
}

struct FishMessengerProfile: Codable, Equatable {
    let relayURL: URL
    let inboxID: String
    let readToken: String
    let deliveryToken: String
    let privateKey: String
    var displayName: String
    var contacts: [FishContact]
}

enum FishMessengerVaultError: Error { case keychain(OSStatus); case invalidState }

final class FishMessengerVault {
    private let service = "com.blobfish.desktop-pet.native.fish-messenger"
    private let account = "profile-v1"

    func load() throws -> FishMessengerProfile? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              data.count <= 64 * 1024,
              let profile = try? JSONDecoder().decode(FishMessengerProfile.self, from: data) else {
            throw FishMessengerVaultError.keychain(status)
        }
        try validate(profile)
        return profile
    }

    func save(_ profile: FishMessengerProfile) throws {
        try validate(profile)
        let data = try JSONEncoder().encode(profile)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateStatus = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insert = base
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(insert as CFDictionary, nil)
            guard status == errSecSuccess else { throw FishMessengerVaultError.keychain(status) }
        } else if updateStatus != errSecSuccess {
            throw FishMessengerVaultError.keychain(updateStatus)
        }
    }

    private func validate(_ profile: FishMessengerProfile) throws {
        guard profile.relayURL.scheme == "https", profile.relayURL.host != nil,
              let privateData = Data(base64Encoded: profile.privateKey), privateData.count == 32,
              (try? FishMessengerIdentity(rawPrivateKey: privateData)) != nil,
              profile.contacts.count <= 32,
              Set(profile.contacts.map(\.id)).count == profile.contacts.count else {
            throw FishMessengerVaultError.invalidState
        }
        _ = try FishInvite(
            relayURL: profile.relayURL,
            inboxID: profile.inboxID,
            deliveryToken: profile.deliveryToken,
            publicKey: try FishMessengerIdentity(rawPrivateKey: privateData).publicKey,
            displayName: profile.displayName
        )
        for contact in profile.contacts { _ = try contact.invite.encoded() }
    }
}

struct FishRelayInbox: Decodable {
    let version: Int
    let inboxID: String
    let readToken: String
    let deliveryToken: String
}

struct FishRelayMessage: Decodable {
    let id: String
    let envelope: FishEncryptedEnvelope
    let createdAt: Double
}

enum FishMessengerServiceError: LocalizedError {
    case persistenceFailed(operation: String, detail: String)
    case rejectedUnknownSender
    case rejectedInvalidEnvelope
    case visitsUnavailable

    var errorDescription: String? {
        switch self {
        case .persistenceFailed(let operation, let detail):
            return "Fish messenger could not persist \(operation): \(detail)"
        case .rejectedUnknownSender:
            return "Fish messenger discarded a message from an unknown sender."
        case .rejectedInvalidEnvelope:
            return "Fish messenger discarded a message that failed authentication."
        case .visitsUnavailable:
            return "Fish visits are disabled or this contact is muted."
        }
    }
}

enum FishContactImportPolicy {
    static func validate(_ invite: FishInvite, for profile: FishMessengerProfile) throws {
        guard let privateKey = Data(base64Encoded: profile.privateKey),
              let identity = try? FishMessengerIdentity(rawPrivateKey: privateKey) else {
            throw FishMessengerVaultError.invalidState
        }
        guard invite.relayURL == profile.relayURL,
              invite.publicKey != identity.publicKey,
              !profile.contacts.contains(where: { $0.invite.publicKey == invite.publicKey }),
              profile.contacts.count < 32 else {
            throw FishMessengerError.invalidInvite
        }
    }
}

final class FishRelayClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func createInbox(at relayURL: URL, setupToken: String) async throws -> FishRelayInbox {
        guard setupToken.utf8.count >= 16, setupToken.utf8.count <= 256 else { throw FishMessengerError.invalidInvite }
        return try await request(
            relayURL.appendingPathComponent("v1/inboxes"), method: "POST", token: nil,
            body: Data(), as: FishRelayInbox.self, extraHeaders: ["X-Fish-Setup-Token": setupToken]
        )
    }

    func deliver(_ envelope: FishEncryptedEnvelope, to invite: FishInvite) async throws {
        let body = try JSONEncoder().encode(["envelope": envelope])
        let _: EmptyResponse = try await request(
            invite.relayURL.appendingPathComponent("v1/inboxes/\(invite.inboxID)/messages"),
            method: "POST", token: invite.deliveryToken, body: body, as: EmptyResponse.self,
            acceptedStatuses: [202]
        )
    }

    func receive(profile: FishMessengerProfile) async throws -> [FishRelayMessage] {
        struct Payload: Decodable { let messages: [FishRelayMessage] }
        let payload: Payload = try await request(
            profile.relayURL.appendingPathComponent("v1/inboxes/\(profile.inboxID)"),
            method: "GET", token: profile.readToken, body: nil, as: Payload.self
        )
        return payload.messages
    }

    func acknowledge(_ ids: [String], profile: FishMessengerProfile) async throws {
        guard !ids.isEmpty else { return }
        let body = try JSONEncoder().encode(["ids": ids])
        let _: EmptyResponse = try await request(
            profile.relayURL.appendingPathComponent("v1/inboxes/\(profile.inboxID)/ack"),
            method: "POST", token: profile.readToken, body: body, as: EmptyResponse.self
        )
    }

    private struct EmptyResponse: Decodable {}

    private func request<T: Decodable>(
        _ url: URL,
        method: String,
        token: String?,
        body: Data?,
        as type: T.Type,
        acceptedStatuses: Set<Int> = [200, 201],
        extraHeaders: [String: String] = [:]
    ) async throws -> T {
        guard url.scheme == "https", url.host != nil else { throw FishMessengerError.invalidInvite }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              acceptedStatuses.contains(http.statusCode), data.count <= 64 * 1024 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

@MainActor
final class FishMessengerService: NSObject {
    private let vault: FishMessengerVault
    private let relay: FishRelayClient
    private let friendStore: FishFriendStore
    private(set) var profile: FishMessengerProfile?
    private(set) var preferences: FishFriendPreferences
    private(set) var records: [FishMessageRecord]
    private(set) var activeVisitContactID: UUID?
    private var pollTimer: Timer?
    private var polling = false
    private var stateObservers: [() -> Void] = []
    private var deferredErrors: [Error] = []
    var onMessage: ((FishMessage, FishContact) -> Void)?
    var onError: ((Error) -> Void)? {
        didSet { flushDeferredErrors() }
    }

    init(
        vault: FishMessengerVault = FishMessengerVault(), relay: FishRelayClient = FishRelayClient(),
        supportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BlobfishDesktopPet", isDirectory: true)
    ) {
        self.vault = vault
        self.relay = relay
        friendStore = FishFriendStore(directoryURL: supportDirectory)
        let state = friendStore.load()
        preferences = state.0
        records = FishMessageHistory.bounded(state.1)
        profile = nil
        super.init()
        do {
            profile = try vault.load()
        } catch {
            deferredErrors.append(persistenceError(error, operation: "profile load"))
        }
    }

    var unreadCount: Int { records.filter { $0.direction == .incoming && !$0.isRead }.count }

    func addStateObserver(_ observer: @escaping () -> Void) { stateObservers.append(observer) }

    func updateDisplayName(_ value: String) throws {
        var next = try requiredProfile()
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.utf8.count <= 48 else { throw FishMessengerError.invalidMessage }
        next.displayName = normalized
        try vault.save(next); profile = next; notifyState()
    }

    func updatePreferences(_ value: FishFriendPreferences) {
        preferences = value
        if !value.visitsEnabled { activeVisitContactID = nil }
        persistState(operation: "preferences update")
        notifyState()
    }

    func markRead(_ id: UUID? = nil) {
        var changed = false
        for index in records.indices where records[index].direction == .incoming && (id == nil || records[index].id == id) {
            if !records[index].isRead {
                records[index].isRead = true
                changed = true
            }
        }
        guard changed else { return }
        persistState(operation: "read state update")
        notifyState()
    }

    func markRead(contactID: UUID) {
        var changed = false
        for index in records.indices
        where records[index].contactID == contactID
            && records[index].direction == .incoming
            && !records[index].isRead {
            records[index].isRead = true
            changed = true
        }
        guard changed else { return }
        persistState(operation: "contact read state update")
        notifyState()
    }

    func updateContact(_ contact: FishContact) throws {
        var next = try requiredProfile()
        guard let index = next.contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        next.contacts[index] = contact
        try vault.save(next)
        profile = next
        if activeVisitContactID == contact.id, contact.blocked || contact.muted {
            activeVisitContactID = nil
        }
        notifyState()
    }

    func createProfile(displayName: String, relayURL: URL, setupToken: String) async throws {
        guard profile == nil else { return }
        let identity = FishMessengerIdentity()
        let inbox = try await relay.createInbox(at: relayURL, setupToken: setupToken)
        let next = FishMessengerProfile(
            relayURL: relayURL,
            inboxID: inbox.inboxID,
            readToken: inbox.readToken,
            deliveryToken: inbox.deliveryToken,
            privateKey: identity.rawPrivateKey.base64EncodedString(),
            displayName: displayName,
            contacts: []
        )
        try vault.save(next)
        profile = next
        notifyState()
    }

    func inviteCode() throws -> String {
        guard let profile, let privateKey = Data(base64Encoded: profile.privateKey) else {
            throw FishMessengerVaultError.invalidState
        }
        return try FishInvite(
            relayURL: profile.relayURL,
            inboxID: profile.inboxID,
            deliveryToken: profile.deliveryToken,
            publicKey: try FishMessengerIdentity(rawPrivateKey: privateKey).publicKey,
            displayName: profile.displayName
        ).encoded()
    }

    func addContact(code: String) throws {
        var next = try requiredProfile()
        let invite = try FishInvite.decode(code.trimmingCharacters(in: .whitespacesAndNewlines))
        try FishContactImportPolicy.validate(invite, for: next)
        next.contacts.append(FishContact(invite: invite))
        try vault.save(next)
        profile = next
        notifyState()
    }

    func send(
        text: String, to contactID: UUID, replyTo: UUID? = nil,
        kind: FishMessageKind = .text, presence: FishPresence? = nil
    ) async throws {
        let profile = try requiredProfile()
        guard let contact = profile.contacts.first(where: { $0.id == contactID }), !contact.blocked,
              let privateKey = Data(base64Encoded: profile.privateKey) else { throw FishMessengerError.invalidInvite }
        if kind == .visitStart || kind == .visitAccept {
            guard FishVisitPolicy.canActivate(contact: contact, preferences: preferences) else {
                throw FishMessengerServiceError.visitsUnavailable
            }
        }
        let message = try FishMessage(
            senderName: profile.displayName, text: text, replyTo: replyTo,
            kind: kind, bubbleColor: preferences.bubbleColor, presence: presence
        )
        let envelope = try FishMessengerIdentity(rawPrivateKey: privateKey).encrypt(message, for: contact.invite.publicKey)
        try await relay.deliver(envelope, to: contact.invite)
        FishMessageHistory.append(FishMessageRecord(
            id: message.id, contactID: contact.id, direction: .outgoing, sentAt: message.sentAt,
            senderName: profile.displayName, text: message.text, kind: kind, isRead: true,
            bubbleColor: message.bubbleColor, presence: presence
        ), to: &records)
        activeVisitContactID = FishVisitPolicy.activeContactID(
            after: kind,
            from: contact,
            current: activeVisitContactID,
            preferences: preferences
        )
        persistState(operation: "outgoing message")
        notifyState()
    }

    func start() {
        guard pollTimer == nil, profile != nil else { return }
        pollTimer = Timer.scheduledTimer(timeInterval: 8, target: self, selector: #selector(pollTimerFired), userInfo: nil, repeats: true)
        if let pollTimer { RunLoop.main.add(pollTimer, forMode: .common) }
        Task { await poll() }
    }

    func stop() { pollTimer?.invalidate(); pollTimer = nil }

    @objc private func pollTimerFired() { Task { await poll() } }

    func poll() async {
        guard !polling, let receiveProfile = profile else { return }
        polling = true
        defer { polling = false }
        do {
            let relayRecords = try await relay.receive(profile: receiveProfile)
            var acknowledged: [String] = []
            guard let privateKey = Data(base64Encoded: receiveProfile.privateKey) else {
                throw FishMessengerVaultError.invalidState
            }
            let identity = try FishMessengerIdentity(rawPrivateKey: privateKey)
            var seenMessageIDs = Set(records.map(\.id))
            var stateChanged = false
            var profileChanged = false
            var deliveries: [(FishMessage, FishContact)] = []

            for record in relayRecords {
                acknowledged.append(record.id)
                guard let contact = profile?.contacts.first(where: {
                    $0.invite.publicKey == record.envelope.senderPublicKey
                }) else {
                    report(FishMessengerServiceError.rejectedUnknownSender)
                    continue
                }
                guard !contact.blocked else { continue }

                let message: FishMessage
                do {
                    message = try identity.decrypt(
                        record.envelope,
                        expectedSenderPublicKey: contact.invite.publicKey
                    )
                } catch {
                    report(FishMessengerServiceError.rejectedInvalidEnvelope)
                    continue
                }
                guard seenMessageIDs.insert(message.id).inserted else { continue }

                let kind = message.kind ?? .text
                FishMessageHistory.append(FishMessageRecord(
                    id: message.id, contactID: contact.id, direction: .incoming, sentAt: message.sentAt,
                    senderName: message.senderName, text: message.text, kind: kind, isRead: false,
                    bubbleColor: message.bubbleColor, presence: message.presence
                ), to: &records)
                stateChanged = true

                let canActivateVisit = FishVisitPolicy.canActivate(
                    contact: contact,
                    preferences: preferences
                )
                if canActivateVisit,
                   kind == .visitStart || kind == .visitAccept,
                   let presence = message.presence,
                   let index = profile?.contacts.firstIndex(where: { $0.id == contact.id }),
                   profile?.contacts[index].lastPresence != presence {
                    profile?.contacts[index].lastPresence = presence
                    profileChanged = true
                }
                let nextActiveContactID = FishVisitPolicy.activeContactID(
                    after: kind,
                    from: contact,
                    current: activeVisitContactID,
                    preferences: preferences
                )
                if nextActiveContactID != activeVisitContactID {
                    activeVisitContactID = nextActiveContactID
                    stateChanged = true
                }
                if FishVisitPolicy.shouldPresent(
                    kind: kind,
                    from: contact,
                    preferences: preferences
                ) {
                    deliveries.append((message, contact))
                }
            }

            if profileChanged, let updated = profile {
                do {
                    try vault.save(updated)
                } catch {
                    reportPersistenceFailure(error, operation: "contact presence")
                }
            }
            if stateChanged {
                persistState(operation: "incoming messages")
                notifyState()
            }
            for delivery in deliveries { onMessage?(delivery.0, delivery.1) }
            try await relay.acknowledge(Array(Set(acknowledged)), profile: receiveProfile)
        } catch {
            report(error)
        }
    }

    private func requiredProfile() throws -> FishMessengerProfile {
        guard let profile else { throw FishMessengerVaultError.invalidState }
        return profile
    }

    private func persistState(operation: String) {
        do {
            try friendStore.save(preferences: preferences, records: records)
        } catch {
            reportPersistenceFailure(error, operation: operation)
        }
    }

    private func persistenceError(_ error: Error, operation: String) -> FishMessengerServiceError {
        .persistenceFailed(operation: operation, detail: error.localizedDescription)
    }

    private func reportPersistenceFailure(_ error: Error, operation: String) {
        report(persistenceError(error, operation: operation))
    }

    private func report(_ error: Error) {
        if let onError {
            onError(error)
        } else {
            deferredErrors.append(error)
        }
    }

    private func flushDeferredErrors() {
        guard let onError, !deferredErrors.isEmpty else { return }
        let pending = deferredErrors
        deferredErrors.removeAll()
        for error in pending { onError(error) }
    }

    private func notifyState() { stateObservers.forEach { $0() } }
}
