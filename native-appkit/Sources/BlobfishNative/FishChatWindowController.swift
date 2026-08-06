import AppKit
import Combine
import SwiftUI

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

@MainActor
final class FishChatViewModel: ObservableObject {
    @Published private(set) var contacts: [FishContact] = []
    @Published private(set) var records: [FishMessageRecord] = []
    @Published private(set) var selectedContactID: UUID?
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage = ""

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
            .filter { $0.contactID == selectedContactID }
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
            markSelectedContactReadIfNeeded()
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

    func toggleVisit() {
        guard let contact = selectedContact, !isSending else { return }
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
        onSuccess: (() -> Void)? = nil
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
                onSuccess?()
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

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            conversation
        }
        .frame(minWidth: 600, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(t("魚魚歷史", "Fish History"))
                    .font(.title3.weight(.bold))
                Spacer()
                if model.totalUnreadCount > 0 {
                    Text("\(model.totalUnreadCount)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.red, in: Capsule())
                }
            }
            .padding(16)

            Divider()

            if model.contacts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(t("還沒有配對好友", "No paired friends"))
                        .font(.headline)
                    Text(t("請先在設定中完成魚魚配對。", "Pair a fish in Settings first."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.contacts) { contact in
                            contactButton(contact)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 210)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
    }

    private func contactButton(_ contact: FishContact) -> some View {
        let selected = model.selectedContactID == contact.id
        let unread = model.unreadCount(for: contact.id)
        return Button {
            model.selectContact(contact.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(selected ? .white : .blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(contact.nickname ?? contact.invite.displayName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(contactStatus(contact))
                        .font(.caption2)
                        .foregroundStyle(selected ? Color.white.opacity(0.78) : Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if unread > 0 {
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.caption2.bold())
                        .foregroundStyle(selected ? Color.accentColor : Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(selected ? Color.white : Color.red, in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var conversation: some View {
        if let contact = model.selectedContact {
            VStack(spacing: 0) {
                conversationHeader(contact)
                Divider()
                messageTimeline
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text(t("選擇一位好友開始傳話", "Choose a friend to start chatting"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func conversationHeader(_ contact: FishContact) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.nickname ?? contact.invite.displayName)
                    .font(.headline)
                Text(contactStatus(contact))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !model.errorMessage.isEmpty {
                    Text(model.errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button {
                model.toggleVisit()
            } label: {
                Label(
                    model.isActiveVisit(contact.id)
                        ? t("結束串門", "End Visit")
                        : t("邀請串門", "Invite Over"),
                    systemImage: model.isActiveVisit(contact.id) ? "door.left.hand.open" : "heart.circle"
                )
            }
            .disabled(model.visitButtonDisabled(for: contact))
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    private var messageTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.selectedRecords.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text(t("還沒有對話紀錄", "No messages yet"))
                            .font(.headline)
                        Text(t("可以從右鍵選單另行打開發消息視窗。", "Open the separate message composer from the context menu."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 90)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(model.selectedRecords) { record in
                            FishChatMessageRow(record: record, isEnglish: model.isEnglish)
                                .id(record.id)
                        }
                    }
                    .padding(18)
                }
            }
            .onAppear { scrollToLatest(proxy) }
            .onChange(of: model.selectedContactID) { _ in scrollToLatest(proxy) }
            .onChange(of: model.selectedRecords.count) { _ in scrollToLatest(proxy) }
        }
    }

    private func contactStatus(_ contact: FishContact) -> String {
        if contact.blocked { return t("已封鎖", "Blocked") }
        if model.isActiveVisit(contact.id) { return t("串門中", "Visiting") }
        if contact.muted { return t("已靜音", "Muted") }
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
    @Published var selectedContactID: UUID?
    @Published var draft = ""
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var statusMessage = ""
    @Published private(set) var locale: String

    private let messengerService: FishMessengerService
    private let onSent: @MainActor (FishMessengerService.SendResult, FishContact) -> Void

    init(
        messengerService: FishMessengerService,
        locale: String,
        onSent: @escaping @MainActor (FishMessengerService.SendResult, FishContact) -> Void
    ) {
        self.messengerService = messengerService
        self.locale = locale
        self.onSent = onSent
        refreshContacts(preferredContactID: nil)
        messengerService.addStateObserver { [weak self] in
            self?.refreshContacts(preferredContactID: self?.selectedContactID)
        }
    }

    var isEnglish: Bool { locale == "en" }
    var selectedContact: FishContact? {
        guard let selectedContactID else { return nil }
        return contacts.first { $0.id == selectedContactID }
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

    func updateLocale(_ value: String) { locale = value }

    func prepareToShow(preferredContactID: UUID?) {
        refreshContacts(preferredContactID: preferredContactID)
        errorMessage = ""
        statusMessage = ""
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
                    ? (self.isEnglish ? "Delivered." : "已送達。")
                    : (self.isEnglish
                        ? "Delivered, but the local history could not be saved. Do not resend it."
                        : "已經送達，但本地歷史未能保存，請不要重複發送。")
            } catch {
                self.errorMessage = error.localizedDescription
            }
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

private struct FishMessageComposeView: View {
    @ObservedObject var model: FishMessageComposeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.availableContacts.isEmpty {
                Text(t("還沒有可以傳話的魚友，請先在設定中完成配對。", "Pair a fish in Settings before sending a message."))
                    .foregroundStyle(.secondary)
            } else {
                if model.availableContacts.count > 1 {
                    Picker(t("收件魚友", "Recipient"), selection: $model.selectedContactID) {
                        ForEach(model.availableContacts) { contact in
                            Text(contact.nickname ?? contact.invite.displayName)
                                .tag(Optional(contact.id))
                        }
                    }
                } else if let contact = model.selectedContact {
                    Text(t("傳話給：", "To: ") + (contact.nickname ?? contact.invite.displayName))
                        .font(.headline)
                }

                TextField(t("想讓水滴魚說什麼？", "What should your fish say?"), text: $model.draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.sendMessage() }

                HStack(alignment: .firstTextBaseline) {
                    if model.draftExceedsLimit {
                        Text("\(model.draftByteCount) / \(FishMessage.maximumTextBytes) UTF-8")
                            .foregroundStyle(.red)
                    } else if !model.errorMessage.isEmpty {
                        Text(model.errorMessage).foregroundStyle(.red).lineLimit(2)
                    } else if !model.statusMessage.isEmpty {
                        Text(model.statusMessage).foregroundStyle(.secondary).lineLimit(2)
                    } else {
                        Text(t("最多 1,000 個 UTF-8 字節。", "Up to 1,000 UTF-8 bytes."))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.isSending ? t("發送中…", "Sending…") : t("發送", "Send")) {
                        model.sendMessage()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(model.sendDisabled)
                }
                .font(.caption)
            }
        }
        .padding(18)
        .frame(width: 460)
    }

    private func t(_ zh: String, _ en: String) -> String { model.isEnglish ? en : zh }
}

@MainActor
final class FishMessageComposeWindowController: NSWindowController {
    private let viewModel: FishMessageComposeViewModel
    private var latestSceneAnchor: PetSceneAnchor?

    init(
        messengerService: FishMessengerService,
        locale: String,
        onSent: @escaping @MainActor (FishMessengerService.SendResult, FishContact) -> Void
    ) {
        let viewModel = FishMessageComposeViewModel(
            messengerService: messengerService,
            locale: locale,
            onSent: onSent
        )
        self.viewModel = viewModel
        let hosting = NSHostingController(rootView: FishMessageComposeView(model: viewModel))
        let window = NSWindow(contentViewController: hosting)
        window.title = locale == "en" ? "Send Fish Message" : "讓魚傳話"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    func showComposer(
        preferredContactID: UUID? = nil,
        sceneAnchor: PetSceneAnchor? = nil
    ) {
        if let sceneAnchor { latestSceneAnchor = sceneAnchor }
        viewModel.prepareToShow(preferredContactID: preferredContactID)
        showWindow(nil)
        window?.contentView?.layoutSubtreeIfNeeded()
        repositionIfVisible()
    }

    func updateSceneAnchor(_ sceneAnchor: PetSceneAnchor) {
        latestSceneAnchor = sceneAnchor
        repositionIfVisible()
    }

    func updateLocale(_ locale: String) {
        viewModel.updateLocale(locale)
        window?.title = locale == "en" ? "Send Fish Message" : "讓魚傳話"
    }

    private func repositionIfVisible() {
        guard let window, let latestSceneAnchor else { return }
        let proposed = PetAttachedWindowGeometry.frame(
            windowSize: window.frame.size,
            anchor: latestSceneAnchor
        )
        guard PetAttachedWindowGeometry.shouldReposition(
            isWindowVisible: window.isVisible,
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

    var body: some View {
        HStack(alignment: .bottom) {
            if record.direction == .outgoing { Spacer(minLength: 72) }
            VStack(alignment: record.direction == .incoming ? .leading : .trailing, spacing: 4) {
                if record.direction == .incoming {
                    Text(record.senderName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(displayText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .foregroundStyle(record.direction == .outgoing ? Color.white : Color.primary)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: 12))
                Text(record.sentAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if record.direction == .incoming { Spacer(minLength: 72) }
        }
        .frame(maxWidth: .infinity)
    }

    private var displayText: String {
        switch record.kind {
        case .text: return record.text
        case .visitStart: return (isEnglish ? "Visit invitation: " : "串門邀請：") + record.text
        case .visitAccept: return (isEnglish ? "Visit accepted: " : "已接受串門：") + record.text
        case .visitEnd: return (isEnglish ? "Visit ended: " : "串門結束：") + record.text
        }
    }

    private var bubbleColor: Color {
        if record.direction == .outgoing {
            return Color.fishChatHex(record.bubbleColor) ?? .accentColor
        }
        return Color.fishChatHex(record.bubbleColor)?.opacity(0.16)
            ?? Color(nsColor: .controlBackgroundColor)
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
        let window = NSWindow(contentViewController: hosting)
        window.title = locale == "en" ? "Fish History" : "魚魚歷史"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 680, height: 520))
        window.minSize = NSSize(width: 600, height: 420)
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
