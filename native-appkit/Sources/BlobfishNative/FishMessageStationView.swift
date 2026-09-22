import AppKit
import SwiftUI

// Share content dimensions with AppKit; the native title bar sits outside.
enum FishComposeLayout {
    static let interactionRowHeight: CGFloat = 40
    static let interactionSpacing: CGFloat = 4
    static var interactionGridHeight: CGFloat {
        let rows = (FishRemoteInteraction.allCases.count + 2) / 3
        return CGFloat(rows) * interactionRowHeight + CGFloat(max(0, rows - 1)) * interactionSpacing
    }
    static func contentSize(hasIncoming: Bool, interactionsExpanded: Bool = false) -> NSSize {
        let baseHeight: CGFloat = hasIncoming ? 206 : 160
        return NSSize(width: 240, height: baseHeight + (interactionsExpanded ? interactionGridHeight + 6 : 0))
    }
}

struct FishStationPalette {
    let dark: Bool
    var backdrop: Color { dark ? Color(red: 0.16, green: 0.12, blue: 0.15) : Color(red: 0.98, green: 0.94, blue: 0.95) }
    var paper: Color { dark ? Color(red: 0.23, green: 0.20, blue: 0.22) : Color(red: 1, green: 0.985, blue: 0.96) }
    var ink: Color { dark ? Color(red: 0.98, green: 0.92, blue: 0.93) : Color(red: 0.30, green: 0.16, blue: 0.22) }
    var muted: Color { dark ? Color(red: 0.82, green: 0.72, blue: 0.77) : Color(red: 0.48, green: 0.32, blue: 0.38) }
    var stamp: Color { Color(red: 0.61, green: 0.21, blue: 0.35) }
}

struct FishMessageComposeView: View {
    @ObservedObject var model: FishMessageComposeViewModel
    @Environment(\.colorScheme) private var colorScheme
    private var palette: FishStationPalette { FishStationPalette(dark: colorScheme == .dark) }
    private var size: NSSize { FishComposeLayout.contentSize(hasIncoming: !model.unreadIncomingMessages.isEmpty, interactionsExpanded: model.interactionsExpanded) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.availableContacts.isEmpty {
                Label(t("還沒有魚友", "No fish friends yet"), systemImage: "envelope")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(t("先在設定中配對，就可以傳話了。", "Pair a friend in Settings to start writing."))
                    .font(.system(size: 12)).foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                recipient.frame(height: 22)
                if !model.unreadIncomingMessages.isEmpty { incomingMail }
                editor.frame(height: 58)
                interactionPanel
                footer.frame(height: 24)
            }
        }
        .padding(8)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(palette.backdrop)
        .foregroundStyle(palette.ink)
        .tint(palette.stamp)
    }

    private var interactionPanel: some View {
        VStack(spacing: 6) {
            Button { model.interactionsExpanded.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: model.interactionsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text(t("互動", "Interactions")).font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 7)
                .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22)
                .background(palette.paper.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(model.interactionsExpanded ? t("已展開", "Expanded") : t("已收起", "Collapsed"))
            if model.interactionsExpanded {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: FishComposeLayout.interactionSpacing) {
                    ForEach(FishRemoteInteraction.allCases) { interaction in
                        Button { model.sendInteraction(interaction) } label: {
                            VStack(spacing: 3) {
                                Image(systemName: interaction.symbolName).font(.system(size: 13))
                                Text(InterfaceLanguage.authored(interaction.title(isEnglish: model.isEnglish), locale: model.locale))
                                    .font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity, minHeight: FishComposeLayout.interactionRowHeight, maxHeight: FishComposeLayout.interactionRowHeight)
                            .background(palette.paper.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isSending || model.selectedContact == nil)
                    }
                }
                .frame(height: FishComposeLayout.interactionGridHeight)
            }
        }
    }

    private var recipient: some View {
        HStack(spacing: 5) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 11)).foregroundStyle(palette.muted).accessibilityHidden(true)
            if model.availableContacts.count > 1 {
                Picker(t("收件魚友", "Recipient"), selection: $model.selectedContactID) {
                    ForEach(model.availableContacts) { contact in
                        Text(contact.nickname ?? contact.invite.displayName).tag(Optional(contact.id))
                    }
                }
                .labelsHidden().controlSize(.small)
                .frame(maxWidth: .infinity).disabled(model.isSending)
            } else if let contact = model.selectedContact {
                Text(contact.nickname ?? contact.invite.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1).help(contact.nickname ?? contact.invite.displayName)
                Spacer(minLength: 0)
            }
            HStack(spacing: 2) {
                ForEach(model.quickInteractions) { interaction in
                    Button { model.sendInteraction(interaction) } label: {
                        Image(systemName: interaction.symbolName)
                            .frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .help(interaction.title(isEnglish: model.isEnglish))
                    .accessibilityLabel(interaction.title(isEnglish: model.isEnglish))
                }
            }
            .font(.system(size: 12)).buttonStyle(.plain).fixedSize()
            .disabled(model.isSending || model.selectedContact == nil)
            visitButton
        }
    }

    private var visitButton: some View {
        Button { model.toggleVisit() } label: {
            HStack(spacing: 3) {
                Image(systemName: model.isWaitingForVisit ? "phone.down.fill" : model.isActiveVisit ? "house.fill" : "door.left.hand.open")
                    .font(.system(size: 11, weight: .semibold))
                Text(model.isWaitingForVisit ? t("取消", "Cancel") : model.isActiveVisit ? t("回家", "Home") : t("串門", "Visit"))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(width: 56, height: 22)
        }
        .buttonStyle(FishVisitDoorplateButtonStyle(dark: colorScheme == .dark, active: model.isActiveVisit))
        .fixedSize()
        .padding(.leading, 3)
        .help(visitTitle).accessibilityLabel(visitTitle)
        .disabled(model.isSending || model.selectedContact == nil)
    }

    private var visitTitle: String {
        model.isWaitingForVisit ? t("取消呼叫", "Cancel call") : model.isChangingVisit ? t("處理中…", "Please wait…")
            : (model.isActiveVisit ? t("回自己家", "Head home") : t("去串門", "Visit friend"))
    }

    private var incomingMail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                // Keep all captured letters reachable, not just the last six.
                ForEach(model.unreadIncomingMessages) { message in
                    Text(message.text).font(.system(size: 12)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
        }
        .frame(height: 40)
        .background(palette.paper, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(t("新來信", "Incoming mail"))
    }

    private var editor: some View {
        FishComposeEditor(text: $model.draft, ink: NSColor(palette.ink),
                          placeholder: t("說點什麼…", "Say something…"),
                          placeholderColor: NSColor(palette.muted),
                          accessibilityLabel: t("傳話內容", "Message"),
                          onSend: sendMessageSafely)
        .background(palette.paper, in: RoundedRectangle(cornerRadius: 7))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(statusText).font(.system(size: 10))
                .foregroundStyle(model.draftExceedsLimit || !model.errorMessage.isEmpty ? .red : palette.muted)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                .help(statusText).accessibilityLabel(statusText)
            Button(action: sendMessageSafely) {
                Label(model.isSending ? t("傳送中", "Sending") : t("寄出", "Send"), systemImage: "arrow.up")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 9).frame(height: 24)
                    .foregroundStyle(.white).background(palette.stamp, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.sendDisabled).opacity(model.sendDisabled ? 0.55 : 1)
            .help(t("Enter 寄出 · ⌘↩ 換行", "Enter to send · ⌘↩ for a new line"))
        }
    }

    private var statusText: String {
        if model.draftExceedsLimit {
            return t("內容太長，請縮短", "Message too long")
                + " (\(model.draftByteCount)/\(FishMessage.maximumTextBytes))"
        }
        if !model.errorMessage.isEmpty { return model.errorMessage }
        if !model.statusMessage.isEmpty { return model.statusMessage }
        return t("↩ 寄出 · ⌘↩ 換行", "↩ Send · ⌘↩ New line")
    }

    private func sendMessageSafely() {
        // Preserve unfinished Chinese/Japanese IME composition and focus.
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() { return }
        model.sendMessage()
    }

    private func t(_ zh: String, _ en: String) -> String { model.isEnglish ? en : zh }
}

private struct FishVisitDoorplateButtonStyle: ButtonStyle {
    let dark: Bool
    let active: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fill = active
            ? Color(red: 0.61, green: 0.21, blue: 0.35)
            : (dark ? Color(red: 0.93, green: 0.70, blue: 0.77) : Color(red: 0.97, green: 0.79, blue: 0.83))
        configuration.label
            .foregroundStyle(active ? Color.white : Color(red: 0.34, green: 0.12, blue: 0.22))
            .background(fill, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
    }
}
