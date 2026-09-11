import AppKit
import SwiftUI

struct CodexQuestionPage: Identifiable, Equatable {
    let request: CodexQuestionRequest
    let question: CodexQuestion
    var id: String { "\(request.threadID)|\(request.turnID)|\(request.id)|\(question.id)" }
}

@MainActor final class CodexQuestionViewModel: ObservableObject {
    @Published var pages: [CodexQuestionPage] = []
    @Published var index = 0
    @Published var locale = "zh-CN"
    @Published var navigationError = false
    var page: CodexQuestionPage? { pages.indices.contains(index) ? pages[index] : nil }
    func t(_ zh: String, _ en: String) -> String { locale == "en" ? en : zh }
    func synchronize(_ requests: [CodexQuestionRequest]) {
        let selected = page?.id
        let next = requests.flatMap { request in request.questions.map { CodexQuestionPage(request: request, question: $0) } }
        guard next != pages else { return }
        pages = next
        index = selected.flatMap { id in pages.firstIndex { $0.id == id } } ?? min(index, max(0, pages.count - 1))
        navigationError = false
    }
    func openInCodex() {
        guard let page, CodexObservationReducer.identifier(page.request.threadID) != nil,
              let url = URL(string: "codex://threads/\(page.request.threadID)") else { return }
        navigationError = !NSWorkspace.shared.open(url)
    }
}

private struct CodexQuestionView: View {
    @ObservedObject var model: CodexQuestionViewModel
    @Environment(\.colorScheme) private var scheme
    private var accent: Color { scheme == .dark ? Color(red: 0.98, green: 0.64, blue: 0.74) : Color(red: 0.61, green: 0.24, blue: 0.36) }
    private var paper: Color { scheme == .dark ? Color(red: 0.17, green: 0.13, blue: 0.15) : Color(red: 1, green: 0.96, blue: 0.97) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill").foregroundStyle(accent)
                Text(model.t("鱼鱼递来一个问题", "A question, delivered"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                Text("\(min(model.index + 1, model.pages.count))/\(model.pages.count)")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            if let page = model.page {
                HStack {
                    Text("Codex · \(String(page.request.threadID.suffix(6)))")
                    Spacer()
                    Text(page.request.blocking ? model.t("等你回答", "Awaiting you") : model.t("边做边问", "Still working"))
                        .foregroundStyle(accent)
                }.font(.system(size: 11))
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(verbatim: page.question.title)
                            .font(.system(size: 14, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            .padding(.bottom, 3)
                        ForEach(Array(page.question.options.enumerated()), id: \.offset) { index, option in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1)").font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(accent).frame(width: 19, height: 19)
                                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: option.label).font(.system(size: 12, weight: .semibold))
                                    if !option.description.isEmpty {
                                        Text(verbatim: option.description).font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(9).background(Color(nsColor: .textBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
                            .accessibilityElement(children: .combine)
                        }
                        if page.question.options.isEmpty {
                            Text(model.t("这题可以自由回答。", "This question accepts a free-text answer."))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .id(page.id)
                Divider().overlay(accent.opacity(0.12))
                HStack(spacing: 8) {
                    Button { model.index -= 1 } label: { Image(systemName: "chevron.left") }
                        .disabled(model.index == 0).accessibilityLabel(model.t("上一题", "Previous question"))
                    Button { model.index += 1 } label: { Image(systemName: "chevron.right") }
                        .disabled(model.index + 1 >= model.pages.count).accessibilityLabel(model.t("下一题", "Next question"))
                    Spacer(minLength: 0)
                    Button { model.openInCodex() } label: {
                        Text(model.t("回 Codex 回答 ↗", "Answer in Codex ↗"))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .foregroundStyle(scheme == .dark ? Color(red: 0.17, green: 0.13, blue: 0.15) : .white)
                            .background(accent, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }.controlSize(.small)
                Text(model.navigationError
                     ? model.t("未能打开 Codex，请手动切回原任务。", "Could not open Codex. Return to the original task manually.")
                     : model.t("可滚动阅读 · 选项仅预览，不在此提交", "Scroll to read · Preview only, answer in Codex"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13).frame(width: 300, height: 340).background(paper)
    }
}

@MainActor final class CodexQuestionWindowController: NSWindowController, NSWindowDelegate {
    let model = CodexQuestionViewModel()
    private var dismissed = Set<String>()
    private var lastRequestIDs = Set<String>()
    init() {
        let host = NSHostingController(rootView: CodexQuestionView(model: model))
        let panel = FishMessagePanel(hosting: host)
        panel.setContentSize(CGSize(width: 300, height: 340))
        super.init(window: panel)
        panel.delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func synchronize(_ requests: [CodexQuestionRequest], locale: String, anchor: PetSceneAnchor?) {
        if model.locale != locale { model.locale = locale }
        let ids = Set(requests.map { "\($0.threadID)|\($0.turnID)|\($0.id)" })
        dismissed.formIntersection(ids)
        let newIDs = ids.subtracting(lastRequestIDs)
        lastRequestIDs = ids
        model.synchronize(requests)
        window?.title = model.t("Codex 问题", "Codex Questions")
        guard !model.pages.isEmpty else { window?.orderOut(nil); return }
        if let anchor { updateAnchor(anchor, force: true) }
        // Background delivery never steals keyboard focus or reopens a dismissed request.
        if !newIDs.subtracting(dismissed).isEmpty { window?.orderFront(nil) }
    }
    func updateAnchor(_ anchor: PetSceneAnchor, force: Bool = false) {
        guard let window, force || window.isVisible else { return }
        let frame = PetAttachedWindowGeometry.frame(windowSize: window.frame.size, anchor: anchor)
        if window.frame.origin != frame.origin { window.setFrameOrigin(frame.origin) }
    }
    func windowWillClose(_ notification: Notification) { dismissed.formUnion(lastRequestIDs) }
}
