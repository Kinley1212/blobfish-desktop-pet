import AppKit
import SwiftUI

// Share content dimensions with AppKit; the native title bar sits outside.
enum FishComposeLayout {
    static func contentSize(hasIncoming: Bool) -> NSSize {
        NSSize(width: 240, height: hasIncoming ? 178 : 132)
    }
}

private struct FishStationPalette {
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
    private var size: NSSize { FishComposeLayout.contentSize(hasIncoming: !model.unreadIncomingMessages.isEmpty) }

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
                footer.frame(height: 24)
            }
        }
        .padding(8)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(palette.backdrop)
        .foregroundStyle(palette.ink)
        .tint(palette.stamp)
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
            Menu {
                ForEach(model.quickInteractions) { interaction in
                    Button { model.sendInteraction(interaction) } label: {
                        Label(interaction.title(isEnglish: model.isEnglish), systemImage: interaction.symbolName)
                    }
                }
                Divider()
                Button { model.toggleVisit() } label: {
                    Label(visitTitle, systemImage: model.isActiveVisit ? "house.fill" : "door.left.hand.open")
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 15))
                    .frame(width: 24, height: 22).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .disabled(model.isSending || model.selectedContact == nil)
            .accessibilityLabel(t("互動與串門", "Gestures and visits"))
            .help(t("互動與串門", "Gestures and visits"))
        }
    }

    private var visitTitle: String {
        model.isChangingVisit ? t("處理中…", "Please wait…")
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
        ZStack(alignment: .topLeading) {
            FishComposeEditor(text: $model.draft, ink: NSColor(palette.ink),
                              accessibilityLabel: t("傳話內容", "Message"),
                              onSend: sendMessageSafely)
            if model.draft.isEmpty {
                Text(t("說點什麼…", "Say something…"))
                    .font(.system(size: 13)).foregroundStyle(palette.muted)
                    .padding(.leading, 5).padding(.top, 8)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
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
