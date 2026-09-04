import AppKit
import SwiftUI

// A compact, code-native post office: warm paper, a rose envelope and a
// vertical action rail. Explicit light/dark pairs avoid pale-paper/white-text
// mismatches; no image generation, external assets or continuous animation.
private struct FishStationPalette {
    let dark: Bool
    var backdrop: Color { dark ? Color(red: 0.16, green: 0.12, blue: 0.15) : Color(red: 0.98, green: 0.94, blue: 0.95) }
    var paper: Color { dark ? Color(red: 0.23, green: 0.20, blue: 0.22) : Color(red: 1, green: 0.985, blue: 0.96) }
    var envelope: Color { dark ? Color(red: 0.42, green: 0.23, blue: 0.31) : Color(red: 0.95, green: 0.70, blue: 0.77) }
    var fold: Color { dark ? Color(red: 0.50, green: 0.28, blue: 0.37) : Color(red: 0.99, green: 0.79, blue: 0.83) }
    var ink: Color { dark ? Color(red: 0.98, green: 0.92, blue: 0.93) : Color(red: 0.30, green: 0.16, blue: 0.22) }
    var muted: Color { dark ? Color(red: 0.82, green: 0.72, blue: 0.77) : Color(red: 0.48, green: 0.32, blue: 0.38) }
    var stamp: Color { Color(red: 0.61, green: 0.21, blue: 0.35) }
}

private struct EnvelopeFold: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.height * 0.58))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct ShellDoor: View {
    let open: Bool
    let palette: FishStationPalette

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(0..<5) { index in
                Ellipse()
                    .fill(index.isMultiple(of: 2) ? palette.fold : palette.envelope)
                    .frame(width: 16, height: 31)
                    .rotationEffect(.degrees(Double(index - 2) * 24), anchor: .bottom)
            }
            RoundedRectangle(cornerRadius: 8)
                .fill(open ? palette.ink : palette.stamp)
                .frame(width: open ? 14 : 5, height: 20)
            Ellipse().fill(palette.fold).frame(width: 38, height: 7).offset(y: 3)
        }
        .frame(width: 54, height: 38)
        .accessibilityHidden(true)
    }
}

struct FishMessageComposeView: View {
    @ObservedObject var model: FishMessageComposeViewModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var writing: Bool
    private var palette: FishStationPalette { FishStationPalette(dark: colorScheme == .dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.fill")
                Text(t("魚魚小郵局", "Fish post office")).font(.system(.headline, design: .rounded))
                Spacer()
            }
            .foregroundStyle(palette.ink)

            if model.availableContacts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(t("信紙準備好了。", "The paper is ready.")).font(.headline)
                    Text(t("還沒有可以傳話的魚友，請先在設定中完成配對。", "Pair a fish in Settings before writing your first letter."))
                        .foregroundStyle(palette.muted)
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(palette.paper, in: RoundedRectangle(cornerRadius: 14))
            } else {
                HStack(alignment: .top, spacing: 10) {
                    letter
                    actionRail
                }
                status
            }
        }
        .padding(12)
        .frame(width: 360, height: 356)
        .background(palette.backdrop)
        .foregroundStyle(palette.ink)
        .tint(palette.stamp)
    }

    private var letter: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                recipient
                if !model.unreadIncomingMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t("新來信", "Incoming mail"))
                            .font(.caption.weight(.semibold)).foregroundStyle(palette.muted)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(model.unreadIncomingMessages.suffix(6)) { message in
                                    Text(message.text).font(.callout).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(height: 44)
                    }
                }
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $model.draft)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .focused($writing)
                        .onAppear { writing = true }
                        .accessibilityLabel(t("信件正文", "Letter body"))
                    if model.draft.isEmpty {
                        Text(t("想說的話，寫在這裡……", "Write a little note…"))
                            .font(.system(size: 14)).foregroundStyle(palette.muted)
                            .padding(.leading, 5).padding(.top, 8)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.paper, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 6).padding(.top, 6)

            HStack(spacing: 6) {
                Text(t("⌘↩ 寄出", "⌘↩ Send"))
                    .font(.caption).foregroundStyle(palette.ink)
                Spacer(minLength: 0)
                Button(action: sendMessageSafely) {
                    Label(model.isSending ? t("忙碌中", "Busy") : t("寄出", "Send"), systemImage: "envelope.fill")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(palette.stamp, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(model.sendDisabled)
                .opacity(model.sendDisabled ? 0.55 : 1)
                .help(t("寄出信件（Command + Return）", "Send letter (Command + Return)"))
            }
            .padding(10)
            .background(EnvelopeFold().fill(palette.fold).accessibilityHidden(true))
        }
        .background(palette.envelope, in: RoundedRectangle(cornerRadius: 15))
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }

    private var recipient: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t("寄給", "To")).font(.caption).foregroundStyle(palette.muted)
            if model.availableContacts.count > 1 {
                Picker(t("收件魚友", "Recipient"), selection: $model.selectedContactID) {
                    ForEach(model.availableContacts) { contact in
                        Text(contact.nickname ?? contact.invite.displayName).tag(Optional(contact.id))
                    }
                }
                .labelsHidden().controlSize(.small)
                .disabled(model.isSending)
            } else if let contact = model.selectedContact {
                Text(contact.nickname ?? contact.invite.displayName)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .help(contact.nickname ?? contact.invite.displayName)
            }
        }
    }

    private var actionRail: some View {
        VStack(spacing: 7) {
            Text(t("輕輕碰一下", "Little gestures"))
                .font(.caption).foregroundStyle(palette.muted)
            ForEach(model.quickInteractions) { interaction in
                Button { model.sendInteraction(interaction) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: interaction.symbolName).font(.system(size: 16))
                        Text(interaction.title(isEnglish: model.isEnglish))
                            .font(.caption).multilineTextAlignment(.center).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .padding(.vertical, 3)
                    .background(palette.paper, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(model.isSending || model.selectedContact == nil)
            }
            Spacer(minLength: 2)
            Button { model.toggleVisit() } label: {
                VStack(spacing: 3) {
                    ShellDoor(open: model.isActiveVisit, palette: palette)
                    Text(model.isChangingVisit ? t("處理中…", "Please wait…") : (model.isActiveVisit ? t("回自己家", "Head home") : t("去串門", "Visit friend")))
                        .font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isSending || model.selectedContact == nil)
            .help(model.isActiveVisit ? t("結束與這位魚友的串門", "End this visit") : t("去這位魚友家串門", "Visit this fish friend"))
        }
        .frame(width: 86)
        .opacity(model.isSending ? 0.6 : 1)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.draftExceedsLimit {
                Text("\(model.draftByteCount) / \(FishMessage.maximumTextBytes) UTF-8")
                    .foregroundStyle(.red)
            } else if !model.errorMessage.isEmpty {
                Text(model.errorMessage).foregroundStyle(.red)
            } else if !model.statusMessage.isEmpty {
                Text(model.statusMessage).foregroundStyle(palette.muted)
            } else {
                Text(t("Enter 換行 · 最多 1,000 UTF-8 字節", "Enter for a new line · 1,000 UTF-8 bytes max"))
                    .foregroundStyle(palette.muted)
            }
        }
        .font(.caption).lineLimit(2)
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .topLeading)
    }

    private func sendMessageSafely() {
        // Do not submit or discard an in-progress Chinese/Japanese IME
        // composition. TextEditor keeps the binding current without resigning
        // first responder (which could otherwise steal the user's next input).
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() { return }
        model.sendMessage()
    }

    private func t(_ zh: String, _ en: String) -> String { model.isEnglish ? en : zh }
}
