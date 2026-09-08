import AppKit
import Combine
import SwiftUI

// The style must be set when constructing the panel, not toggled after it is
// created: AppKit's non-activation event routing is established at creation.
final class FishMessagePanel: NSPanel {
    init(hosting: NSViewController, resizable: Bool = false) {
        var style: NSWindow.StyleMask = [.titled, .closable, .nonactivatingPanel]
        if resizable { style.formUnion([.resizable, .miniaturizable]) }
        super.init(contentRect: .zero, styleMask: style, backing: .buffered, defer: false)
        contentViewController = hosting
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

enum FishChatDraftPolicy {
    static func shouldClear(
        currentDraft: String,
        draftAtSend: String,
        selectedContactID: UUID?,
        sentContactID: UUID
    ) -> Bool {
        selectedContactID == sentContactID && currentDraft == draftAtSend
    }
}

enum FishHistorySelectionPolicy {
    static func select(
        availableContactIDs: [UUID],
        requestedContactID: UUID?,
        newestUnreadContactID: UUID?,
        currentContactID: UUID?,
        preferUnread: Bool
    ) -> UUID? {
        let available = Set(availableContactIDs)
        if let requestedContactID, available.contains(requestedContactID) {
            return requestedContactID
        }
        if preferUnread, let newestUnreadContactID, available.contains(newestUnreadContactID) {
            return newestUnreadContactID
        }
        if let currentContactID, available.contains(currentContactID) {
            return currentContactID
        }
        return availableContactIDs.first
    }
}

enum FishComposeRecipientPolicy {
    static func select(
        availableContactIDs: [UUID],
        preferredContactID: UUID?,
        activeVisitContactID: UUID?,
        currentContactID: UUID?
    ) -> UUID? {
        let available = Set(availableContactIDs)
        for candidate in [preferredContactID, activeVisitContactID, currentContactID] {
            if let candidate, available.contains(candidate) { return candidate }
        }
        return availableContactIDs.first
    }
}

struct FishConversationDrafts {
    private var values: [UUID: String] = [:]
    subscript(_ contactID: UUID?) -> String {
        get { contactID.flatMap { values[$0] } ?? "" }
        set {
            guard let contactID else { return }
            values[contactID] = newValue.isEmpty ? nil : newValue
        }
    }
    mutating func clearAfterSending(_ sentDraft: String, to contactID: UUID) {
        if values[contactID] == sentDraft { values[contactID] = nil }
    }
}

@MainActor
final class FishChatViewModel: ObservableObject {
    @Published private(set) var contacts: [FishContact] = []
    @Published private(set) var records: [FishMessageRecord] = []
    @Published private(set) var selectedContactID: UUID?
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage = ""
    @Published private var drafts = FishConversationDrafts()

    var draft: String {
        get { drafts[selectedContactID] }
        set { drafts[selectedContactID] = newValue }
    }
    var draftByteCount: Int { draft.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count }
    var sendDisabled: Bool {
        isSending || selectedContact?.blocked != false || draftByteCount == 0
            || draftByteCount > FishMessage.maximumTextBytes
    }

    func sendMessage() {
        guard !sendDisabled, let contact = selectedContact else { return }
        performSend(text: draft.trimmingCharacters(in: .whitespacesAndNewlines),
                    contact: contact, kind: .text, presence: nil, draftAtSend: draft)
    }

    @Published private(set) var locale: String
    private let messengerService: FishMessengerService
    private let presenceProvider: @MainActor () -> FishPresence?
    private let visitPhraseProvider: @MainActor (String, String) -> String
    private let onSent: @MainActor (FishMessengerService.SendResult, FishContact) -> Void
    private var windowIsActive = false

    init(
        messengerService: FishMessengerService,
        locale: String,
        presenceProvider: @escaping @MainActor () -> FishPresence?,
        visitPhraseProvider: @escaping @MainActor (String, String) -> String,
        onSent: @escaping @MainActor (FishMessengerService.SendResult, FishContact) -> Void
    ) {
        self.messengerService = messengerService
        self.locale = locale
        self.presenceProvider = presenceProvider
        self.visitPhraseProvider = visitPhraseProvider
        self.onSent = onSent
        refresh()
        messengerService.addStateObserver { [weak self] in self?.refresh() }
    }

    var isEnglish: Bool { locale == "en" }
    func updateLocale(_ value: String) {
        locale = value
    }

    var selectedContact: FishContact? {
        guard let selectedContactID else { return nil }
        return contacts.first { $0.id == selectedContactID }
    }
    var selectedRecords: [FishMessageRecord] {
        guard let selectedContactID else { return [] }
        return records
            .filter {
                $0.contactID == selectedContactID && $0.kind != .status && $0.kind != .receipt
            }
            .sorted { $0.sentAt < $1.sentAt }
    }

    var totalUnreadCount: Int {
        records.filter { $0.direction == .incoming && !$0.isRead }.count
    }

    func unreadCount(for contactID: UUID) -> Int {
        records.filter {
            $0.contactID == contactID && $0.direction == .incoming && !$0.isRead
        }.count
    }

    func isActiveVisit(_ contactID: UUID) -> Bool {
        messengerService.activeVisitContactID == contactID
    }

    func refresh() {
        contacts = messengerService.profile?.contacts ?? []
        records = messengerService.records
        selectedContactID = FishHistorySelectionPolicy.select(
            availableContactIDs: contacts.map(\.id),
            requestedContactID: nil,
            newestUnreadContactID: records
                .filter({ $0.direction == .incoming && !$0.isRead })
                .max(by: { $0.sentAt < $1.sentAt })?.contactID,
            currentContactID: selectedContactID,
            preferUnread: selectedContactID == nil
        )
        markSelectedContactReadIfNeeded()
    }

    func prepareToShow(contactID: UUID?, preferUnread: Bool) {
        refresh()
        selectedContactID = FishHistorySelectionPolicy.select(
            availableContactIDs: contacts.map(\.id),
            requestedContactID: contactID,
            newestUnreadContactID: records
                .filter({ $0.direction == .incoming && !$0.isRead })
                .max(by: { $0.sentAt < $1.sentAt })?.contactID,
            currentContactID: selectedContactID,
            preferUnread: preferUnread
        )
        errorMessage = ""
        markSelectedContactReadIfNeeded()
    }

    func setWindowActive(_ active: Bool) {
        windowIsActive = active
        if active {
            refresh()
        }
    }

    func selectContact(_ id: UUID) {
        guard selectedContactID != id else {
            markSelectedContactReadIfNeeded()
            return
        }
        selectedContactID = id
        errorMessage = ""
        markSelectedContactReadIfNeeded()
    }

    func retryMessage(_ recordID: UUID) {
        errorMessage = ""
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.messengerService.retry(recordID: recordID)
                self.refresh()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func toggleVisit() {
        guard let contact = selectedContact, !contact.blocked, !isSending else { return }
        if isActiveVisit(contact.id) {
            let text = visitPhraseProvider(
                "messenger.visitEnd",
                isEnglish ? "See you next time." : "下次再玩。"
            )
            performSend(text: text, contact: contact, kind: .visitEnd, presence: nil)
            return
        }
        guard messengerService.preferences.visitsEnabled,
              !contact.blocked, !contact.muted,
              let presence = presenceProvider() else {
            errorMessage = isEnglish
                ? "Visits are unavailable for this friend."
                : "目前不能邀请这位好友串门。"
            return
        }
        let text = visitPhraseProvider(
            "messenger.visitStart",
            isEnglish ? "Coming over to visit!" : "來串門啦！"
        )
        performSend(text: text, contact: contact, kind: .visitStart, presence: presence)
    }

    func visitButtonDisabled(for contact: FishContact) -> Bool {
        if isActiveVisit(contact.id) { return isSending }
        return isSending || contact.blocked || contact.muted || !messengerService.preferences.visitsEnabled
    }

    private func performSend(
        text: String,
        contact: FishContact,
        kind: FishMessageKind,
        presence: FishPresence?,
        draftAtSend: String? = nil
    ) {
        isSending = true
        errorMessage = ""
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isSending = false }
            do {
                let result = try await self.messengerService.send(
                    text: text,
                    to: contact.id,
                    kind: kind,
                    presence: presence
                )
                if let draftAtSend { self.drafts.clearAfterSending(draftAtSend, to: contact.id) }
                if !result.historyPersisted {
                    self.errorMessage = self.isEnglish
                        ? "Delivered, but the local history could not be saved. Do not resend it."
                        : "已经送达，但本地历史未能保存，请不要重复发送。"
                }
                self.onSent(result, contact)
                self.refresh()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func markSelectedContactReadIfNeeded() {
        guard windowIsActive, let selectedContactID,
              unreadCount(for: selectedContactID) > 0 else { return }
        messengerService.markRead(contactID: selectedContactID)
    }
}

struct FishChatView: View {
    @ObservedObject var model: FishChatViewModel
    @Environment(\.colorScheme) private var colorScheme
    private var palette: FishStationPalette { FishStationPalette(dark: colorScheme == .dark) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            conversation
        }
        .frame(minWidth: 390, minHeight: 260)
        .background(palette.backdrop)
        .foregroundStyle(palette.ink)
        .tint(palette.stamp)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "envelope.fill").foregroundStyle(palette.stamp)
                Text(t("來信", "Letters"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if model.totalUnreadCount > 0 {
                    Text(model.totalUnreadCount > 99 ? "99+" : "\(model.totalUnreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.muted)
                }
            }
            .padding(.horizontal, 9).frame(height: 52)

            Divider()

            if model.contacts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 22))
                        .foregroundStyle(palette.muted)
                    Text(t("還沒有配對好友", "No paired friends"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(t("請先在設定中完成魚魚配對。", "Pair a fish in Settings first."))
                        .font(.caption)
                        .foregroundStyle(palette.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(9)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.contacts) { contact in
                            contactButton(contact)
                        }
                    }
                    .padding(6)
                }
            }
        }
        .frame(width: 104)
        .background(palette.stamp.opacity(colorScheme == .dark ? 0.10 : 0.04))
    }

    private func contactButton(_ contact: FishContact) -> some View {
        let selected = model.selectedContactID == contact.id
        let unread = model.unreadCount(for: contact.id)
        return Button {
            model.selectContact(contact.id)
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(contact.nickname ?? contact.invite.displayName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(contactStatus(contact))
                        .font(.caption2)
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if unread > 0 {
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(palette.stamp, in: Capsule())
                }
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .foregroundStyle(palette.ink)
            .background(selected ? palette.paper : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(contact.nickname ?? contact.invite.displayName)
    }

    @ViewBuilder private var conversation: some View {
        if let contact = model.selectedContact {
            VStack(spacing: 0) {
                conversationHeader(contact)
                Divider()
                messageTimeline
                Divider()
                replyComposer
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 28)).foregroundStyle(palette.stamp)
                Text(t("選一位魚友，寫封小信。", "Choose a fish. Write a little note."))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.muted)
                    .multilineTextAlignment(.center).padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func conversationHeader(_ contact: FishContact) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.nickname ?? contact.invite.displayName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1).help(contact.nickname ?? contact.invite.displayName)
                Text(contactStatus(contact))
                    .font(.caption)
                    .foregroundStyle(palette.muted)
                if !model.errorMessage.isEmpty {
                    Text(model.errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .help(model.errorMessage)
                }
            }
            Spacer()
            Button {
                model.toggleVisit()
            } label: {
                Image(systemName: model.isActiveVisit(contact.id) ? "house.fill" : "door.left.hand.open")
                    .font(.system(size: 14)).frame(width: 28, height: 28)
                    .background(palette.paper, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .help(model.isActiveVisit(contact.id) ? t("回自己家", "Head home") : t("去串門", "Visit friend"))
            .accessibilityLabel(model.isActiveVisit(contact.id) ? t("回自己家", "Head home") : t("去串門", "Visit friend"))
            .disabled(model.visitButtonDisabled(for: contact))
        }
        .padding(.horizontal, 12)
        .frame(height: model.errorMessage.isEmpty ? 52 : 72)
    }

    private var messageTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.selectedRecords.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "envelope.badge")
                            .font(.system(size: 28))
                            .foregroundStyle(palette.stamp)
                        Text(t("還沒有對話紀錄", "No messages yet"))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(t("在下方寫下第一句話吧。", "Write your first message below."))
                            .font(.caption)
                            .foregroundStyle(palette.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(model.selectedRecords) { record in
                            FishChatMessageRow(
                                record: record,
                                isEnglish: model.isEnglish,
                                onRetry: { model.retryMessage(record.id) }
                            )
                                .id(record.id)
                        }
                    }
                    .padding(12)
                }
            }
            .onAppear { scrollToLatest(proxy) }
            .onChange(of: model.selectedContactID) { _ in scrollToLatest(proxy) }
            .onChange(of: model.selectedRecords.count) { _ in scrollToLatest(proxy) }
        }
    }

    private var replyComposer: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                FishComposeEditor(text: $model.draft, ink: NSColor(palette.ink),
                                  accessibilityLabel: t("傳話內容", "Message"), onSend: sendReply)
                    .id(model.selectedContactID)
                    .disabled(model.selectedContact?.blocked != false)
                if model.draft.isEmpty {
                    Text(t("寫給魚友的一句話…", "A little note for your fish…"))
                        .font(.system(size: 12)).foregroundStyle(palette.muted)
                        .padding(.leading, 5).padding(.top, 8)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .frame(height: 44)
            .background(palette.paper, in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 6) {
                Text(model.draftByteCount > FishMessage.maximumTextBytes
                     ? "\(model.draftByteCount)/\(FishMessage.maximumTextBytes) UTF-8"
                     : t("↩ 寄出 · ⌘↩ 換行", "↩ Send · ⌘↩ New line"))
                    .font(.caption2)
                    .foregroundStyle(model.draftByteCount > FishMessage.maximumTextBytes ? Color.red : palette.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: sendReply) {
                    Label(model.isSending ? t("傳送中", "Sending") : t("寄出", "Send"), systemImage: "arrow.up")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 9).frame(height: 24)
                        .foregroundStyle(.white).background(palette.stamp, in: Capsule())
                }
                .buttonStyle(.plain).disabled(model.sendDisabled)
                .opacity(model.sendDisabled ? 0.55 : 1)
            }
        }
        .padding(8)
    }

    private func sendReply() {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() { return }
        model.sendMessage()
    }

    private func contactStatus(_ contact: FishContact) -> String {
        if contact.blocked { return t("已封鎖", "Blocked") }
        if model.isActiveVisit(contact.id) { return t("串門中", "Visiting") }
        if contact.muted { return t("已靜音", "Muted") }
        if let status = contact.lastPresence?.status { return status.title(isEnglish: model.isEnglish) }
        return t("魚友", "Fish friend")
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let id = model.selectedRecords.last?.id else { return }
        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .bottom) }
    }

    private func t(_ zh: String, _ en: String) -> String { model.isEnglish ? en : zh }

}

@MainActor
final class FishMessageComposeViewModel: ObservableObject {
    @Published private(set) var contacts: [FishContact] = []
    @Published var selectedContactID: UUID? {
        didSet {
            guard oldValue != selectedContactID, isPresented else { return }
            displayedUnreadMessages = []
            captureAndMarkUnread()
        }
    }
    @Published var draft = ""
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var statusMessage = ""
    @Published private(set) var displayedUnreadMessages: [FishMessageRecord] = []
    @Published private(set) var isChangingVisit = false
    @Published private(set) var activeVisitContactID: UUID?
    @Published private(set) var locale: String
    private var lastSentRecordID: UUID?

    private let messengerService: FishMessengerService
    private let onSent: @MainActor (FishMessengerService.SendResult, FishContact) -> Void
    private let presenceProvider: @MainActor () -> FishPresence?
    private var isPresented = false

    init(
        messengerService: FishMessengerService,
        locale: String,
        presenceProvider: @escaping @MainActor () -> FishPresence?,
        onSent: @escaping @MainActor (FishMessengerService.SendResult, FishContact) -> Void
    ) {
        self.messengerService = messengerService
        self.locale = locale
        self.presenceProvider = presenceProvider
        self.onSent = onSent
        self.activeVisitContactID = messengerService.activeVisitContactID
        refreshContacts(preferredContactID: nil)
        messengerService.addStateObserver { [weak self] in
            guard let self else { return }
            self.activeVisitContactID = self.messengerService.activeVisitContactID
            self.refreshContacts(preferredContactID: self.selectedContactID)
            if self.isPresented { self.captureAndMarkUnread() }
            self.refreshDeliveryStatus()
        }
    }

    var isEnglish: Bool { locale == "en" }
    var quickInteractions: [FishRemoteInteraction] {
        messengerService.preferences.effectiveQuickInteractions
    }
    var selectedContact: FishContact? {
        guard let selectedContactID else { return nil }
        return contacts.first { $0.id == selectedContactID }
    }
    var unreadIncomingMessages: [FishMessageRecord] {
        displayedUnreadMessages
    }
    var availableContacts: [FishContact] { contacts.filter { !$0.blocked } }
    var draftByteCount: Int {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count
    }
    var draftExceedsLimit: Bool { draftByteCount > FishMessage.maximumTextBytes }
    var sendDisabled: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draftExceedsLimit
            || isSending
            || selectedContact?.blocked != false
    }

    var isActiveVisit: Bool {
        selectedContactID != nil && activeVisitContactID == selectedContactID
    }

    func toggleVisit() {
        guard let contact = selectedContact, !isSending else { return }
        let ending = isActiveVisit
        let text = ending
            ? (isEnglish ? "See you next time." : "下次再玩。")
            : (isEnglish ? "Coming over to visit!" : "來串門啦！")
        let presence = ending ? nil : presenceProvider()
        guard ending || presence != nil else {
            errorMessage = isEnglish ? "Your fish is not ready to visit. Please try again." : "魚魚還沒準備好出門，請稍後再試。"
            return
        }
        isSending = true
        isChangingVisit = true
        errorMessage = ""
        statusMessage = ""
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isSending = false
                self.isChangingVisit = false
            }
            do {
                _ = try await self.messengerService.send(
                    text: text, to: contact.id,
                    kind: ending ? .visitEnd : .visitStart,
                    presence: presence
                )
            } catch { self.errorMessage = error.localizedDescription }
        }
    }

    func updateLocale(_ value: String) { locale = value }

    func prepareToShow(preferredContactID: UUID?) {
        refreshContacts(preferredContactID: preferredContactID)
        errorMessage = ""
        statusMessage = ""
        // Only the key panel may acknowledge messages, not a hidden window
        // preparing its layout before it is shown in the current Space.
        isPresented = false
        displayedUnreadMessages = []
    }

    func setPresented(_ value: Bool) {
        isPresented = value
        if value {
            captureAndMarkUnread()
        } else {
            displayedUnreadMessages = []
        }
    }

    private func captureAndMarkUnread() {
        guard let selectedContactID else {
            displayedUnreadMessages = []
            return
        }
        let unread = messengerService.records.filter {
            $0.contactID == selectedContactID
                && $0.direction == .incoming
                && !$0.isRead
                && $0.kind == .text
        }.sorted { $0.sentAt < $1.sentAt }
        if !unread.isEmpty {
            let existing = Set(displayedUnreadMessages.map(\.id))
            displayedUnreadMessages.append(contentsOf: unread.filter { !existing.contains($0.id) })
        }
        // The compact composer represents one conversation. Mark only that
        // contact's records so unread messages from other fish remain visible.
        messengerService.markRead(contactID: selectedContactID)
    }

    func sendMessage() {
        guard let contact = selectedContact else { return }
        let draftAtSend = draft
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !contact.blocked, !isSending else { return }
        guard text.utf8.count <= FishMessage.maximumTextBytes else {
            errorMessage = isEnglish
                ? "Messages are limited to 1,000 UTF-8 bytes."
                : "傳話內容不能超過 1,000 個 UTF-8 字節。"
            return
        }
        isSending = true
        errorMessage = ""
        statusMessage = ""
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isSending = false }
            do {
                let result = try await self.messengerService.send(text: text, to: contact.id)
                self.lastSentRecordID = result.record.id
                self.messengerService.markRead(contactID: contact.id)
                self.onSent(result, contact)
                if FishChatDraftPolicy.shouldClear(
                    currentDraft: self.draft,
                    draftAtSend: draftAtSend,
                    selectedContactID: self.selectedContactID,
                    sentContactID: contact.id
                ) {
                    self.draft = ""
                }
                self.statusMessage = result.historyPersisted
                    ? (self.isEnglish ? "Sent. Waiting for your friend’s fish." : "已送出，等待對方魚魚收取。")
                    : (self.isEnglish
                        ? "Delivered, but the local history could not be saved. Do not resend it."
                        : "已經送達，但本地歷史未能保存，請不要重複發送。")
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func sendInteraction(_ interaction: FishRemoteInteraction) {
        guard let contact = selectedContact, !contact.blocked, !isSending else { return }
        isSending = true
        errorMessage = ""
        statusMessage = ""
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isSending = false }
            do {
                let result = try await self.messengerService.send(
                    text: interaction.rawValue,
                    to: contact.id,
                    kind: .interaction,
                    interaction: interaction
                )
                self.lastSentRecordID = result.record.id
                self.onSent(result, contact)
                self.statusMessage = self.isEnglish
                    ? "\(interaction.title(isEnglish: true)) sent."
                    : "已送出「\(interaction.title(isEnglish: false))」。"
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshDeliveryStatus() {
        guard let lastSentRecordID,
              let record = messengerService.records.first(where: { $0.id == lastSentRecordID }) else { return }
        switch record.effectiveDeliveryState {
        case .sending:
            statusMessage = isEnglish ? "Sending…" : "傳送中…"
        case .relayed:
            statusMessage = isEnglish ? "Sent. Waiting for your friend’s fish." : "已送出，等待對方魚魚收取。"
        case .delivered:
            statusMessage = isEnglish ? "Delivered to your friend’s fish." : "已送達對方魚魚。"
        case .read:
            statusMessage = isEnglish ? "Read." : "對方已讀。"
        case .failed:
            statusMessage = isEnglish ? "Send failed. Retry from Chat History." : "傳送失敗，可到聊天紀錄重試。"
        case nil:
            break
        }
    }

    private func refreshContacts(preferredContactID: UUID?) {
        contacts = messengerService.profile?.contacts ?? []
        let candidates = contacts.filter { !$0.blocked }
        selectedContactID = FishComposeRecipientPolicy.select(
            availableContactIDs: candidates.map(\.id),
            preferredContactID: preferredContactID,
            activeVisitContactID: messengerService.activeVisitContactID,
            currentContactID: selectedContactID
        )
    }
}


@MainActor
final class FishMessageComposeWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: FishMessageComposeViewModel
    private var incomingLayoutSubscription: AnyCancellable?
    private var latestSceneAnchor: PetSceneAnchor?
    var onVisibilityChanged: ((Bool) -> Void)?

    init(
        messengerService: FishMessengerService,
        locale: String,
        presenceProvider: @escaping @MainActor () -> FishPresence?,
        onSent: @escaping @MainActor (FishMessengerService.SendResult, FishContact) -> Void
    ) {
        let viewModel = FishMessageComposeViewModel(
            messengerService: messengerService,
            locale: locale,
            presenceProvider: presenceProvider,
            onSent: onSent
        )
        self.viewModel = viewModel
        let hosting = NSHostingController(rootView: FishMessageComposeView(model: viewModel))
        let window = FishMessagePanel(hosting: hosting)
        window.title = locale == "en" ? "Send Fish Message" : "讓魚傳話"
        window.setContentSize(FishComposeLayout.contentSize(hasIncoming: false))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        incomingLayoutSubscription = viewModel.$displayedUnreadMessages
            .map { !$0.isEmpty }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] hasIncoming in
                guard let self, let window = self.window else { return }
                let size = FishComposeLayout.contentSize(hasIncoming: hasIncoming)
                if window.contentView?.frame.size != size { window.setContentSize(size) }
                // Hosting may already have adopted the new intrinsic size;
                // still recheck the edge so expanded mail cannot go offscreen.
                if window.isVisible { self.reposition(force: true) }
            }
    }

    func showComposer(
        preferredContactID: UUID? = nil,
        sceneAnchor: PetSceneAnchor? = nil
    ) {
        if let sceneAnchor { latestSceneAnchor = sceneAnchor }
        viewModel.prepareToShow(preferredContactID: preferredContactID)
        window?.contentView?.layoutSubtreeIfNeeded()
        reposition(force: true)
        onVisibilityChanged?(true)
        window?.makeKeyAndOrderFront(nil)
        viewModel.setPresented(window?.isKeyWindow == true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        viewModel.setPresented(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        viewModel.setPresented(false)
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        viewModel.setPresented(false)
        onVisibilityChanged?(false)
    }

    func updateSceneAnchor(_ sceneAnchor: PetSceneAnchor) {
        guard window?.isVisible == true else { return }
        latestSceneAnchor = sceneAnchor
        reposition(force: false)
    }

    func updateLocale(_ locale: String) {
        viewModel.updateLocale(locale)
        window?.title = locale == "en" ? "Send Fish Message" : "讓魚傳話"
    }

    private func reposition(force: Bool) {
        guard let window, let latestSceneAnchor else { return }
        let proposed = PetAttachedWindowGeometry.frame(
            windowSize: window.frame.size,
            anchor: latestSceneAnchor
        )
        guard PetAttachedWindowGeometry.shouldReposition(
            isWindowVisible: window.isVisible,
            force: force,
            currentFrame: window.frame,
            proposedFrame: proposed
        ) else { return }
        window.setFrameOrigin(proposed.origin)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private struct FishChatMessageRow: View {
    let record: FishMessageRecord
    let isEnglish: Bool
    let onRetry: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var palette: FishStationPalette { FishStationPalette(dark: colorScheme == .dark) }

    var body: some View {
        HStack(alignment: .bottom) {
            if record.direction == .outgoing { Spacer(minLength: 24) }
            VStack(alignment: record.direction == .incoming ? .leading : .trailing, spacing: 4) {
                if record.direction == .incoming {
                    Text(record.senderName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.muted)
                }
                Text(displayText)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .foregroundStyle(palette.ink)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: 12))
                    .background(palette.paper, in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 5) {
                    Text(record.sentAt.formatted(date: .omitted, time: .shortened))
                    if let deliveryText {
                        Image(systemName: deliverySymbol)
                        Text(deliveryText)
                    }
                    if record.effectiveDeliveryState == .failed {
                        Button(isEnglish ? "Retry" : "重試", action: onRetry)
                            .buttonStyle(.link)
                            .font(.caption2)
                    }
                }
                .font(.caption2)
                .foregroundStyle(record.effectiveDeliveryState == .failed ? Color.red : palette.muted)
            }
            if record.direction == .incoming { Spacer(minLength: 24) }
        }
        .frame(maxWidth: .infinity)
    }

    private var displayText: String {
        switch record.kind {
        case .text: return record.text
        case .visitStart: return (isEnglish ? "Visit invitation: " : "串門邀請：") + record.text
        case .visitAccept: return (isEnglish ? "Visit accepted: " : "已接受串門：") + record.text
        case .visitEnd: return (isEnglish ? "Visit ended: " : "串門結束：") + record.text
        case .status: return (isEnglish ? "Status updated" : "狀態已更新")
        case .receipt: return isEnglish ? "Delivery updated" : "送達狀態已更新"
        case .interaction:
            let action = record.interaction ?? FishRemoteInteraction(rawValue: record.text)
            let title = action?.title(isEnglish: isEnglish) ?? (isEnglish ? "Fish action" : "魚魚互動")
            if record.direction == .outgoing {
                return (isEnglish ? "You sent: " : "你送出了：") + title
            }
            return (isEnglish ? "Your friend sent: " : "好友送來了：") + title
        }
    }

    private var deliveryText: String? {
        guard let state = record.effectiveDeliveryState else { return nil }
        switch state {
        case .sending: return isEnglish ? "Sending" : "傳送中"
        case .relayed: return isEnglish ? "Sent" : "已送出"
        case .delivered: return isEnglish ? "Delivered" : "已送達"
        case .read: return isEnglish ? "Read" : "已讀"
        case .failed: return isEnglish ? "Failed" : "失敗"
        }
    }

    private var deliverySymbol: String {
        switch record.effectiveDeliveryState {
        case .sending: return "clock"
        case .relayed: return "checkmark"
        case .delivered: return "checkmark.circle"
        case .read: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle"
        case nil: return ""
        }
    }

    private var bubbleColor: Color {
        // Preserve a friend's chosen hue as a soft tint; paired ink stays
        // readable even when the saved color is very pale or very dark.
        let tint = Color.fishChatHex(record.bubbleColor)
            ?? (record.direction == .outgoing ? palette.stamp : .clear)
        let opacity = record.direction == .outgoing ? 0.18 : 0.06
        return tint.opacity(opacity)
    }
}

@MainActor
final class FishChatWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: FishChatViewModel

    init(
        messengerService: FishMessengerService,
        locale: String = "zh-CN",
        presenceProvider: @escaping @MainActor () -> FishPresence?,
        visitPhraseProvider: @escaping @MainActor (String, String) -> String = { _, fallback in fallback },
        onSent: @escaping @MainActor (FishMessengerService.SendResult, FishContact) -> Void = { _, _ in }
    ) {
        let viewModel = FishChatViewModel(
            messengerService: messengerService,
            locale: locale,
            presenceProvider: presenceProvider,
            visitPhraseProvider: visitPhraseProvider,
            onSent: onSent
        )
        self.viewModel = viewModel
        let hosting = NSHostingController(rootView: FishChatView(model: viewModel))
        let window = FishMessagePanel(hosting: hosting, resizable: true)
        window.title = locale == "en" ? "Fish History" : "魚魚歷史"
        window.setContentSize(NSSize(width: 390, height: 300))
        window.minSize = NSSize(width: 350, height: 250)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true
    }

    override func showWindow(_ sender: Any?) {
        viewModel.refresh()
        super.showWindow(sender)
    }

    func showHistory(contactID: UUID? = nil, preferUnread: Bool = false) {
        viewModel.prepareToShow(contactID: contactID, preferUnread: preferUnread)
        showWindow(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        viewModel.setWindowActive(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        viewModel.setWindowActive(false)
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        viewModel.setWindowActive(false)
    }

    func updateLocale(_ locale: String) {
        viewModel.updateLocale(locale)
        window?.title = locale == "en" ? "Fish History" : "魚魚歷史"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private extension Color {
    static func fishChatHex(_ value: String?) -> Color? {
        guard let value else { return nil }
        let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let number = Int(hex, radix: 16) else { return nil }
        return Color(
            red: Double((number >> 16) & 0xff) / 255,
            green: Double((number >> 8) & 0xff) / 255,
            blue: Double(number & 0xff) / 255
        )
    }
}
