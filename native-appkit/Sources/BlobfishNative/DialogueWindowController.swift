import AppKit
import Combine
import SwiftUI

@MainActor
final class DialogueViewModel: ObservableObject {
    struct Choice: Identifiable {
        let id = UUID()
        let label: String
        let action: () -> Void
    }

    @Published var draft = ""
    @Published var isBusy = false
    @Published var notice = ""
    @Published var aiActive = false
    @Published var optionsCollapsed = false
    private var memorySubscription: AnyCancellable?
    private var requestTask: Task<Void, Never>?
    private var generation = UUID()
    private var sessionHistory: [AIChatMessage] = []
    private var lastInput: String?
    private var lastInputTime: AIChatTimestamp?
    private var promptTime = AIChatTimestamp()
    private var localOnlyThisSession = false
    private var configuration: AIChatConfiguration
    private let transport: AIChatTransport
    private let keyProvider: (String) throws -> String
    @Published var prompt = "……"
    @Published var choices: [Choice] = []
    @Published var moodFaceID: String?

    let runtime: AppRuntime
    private var pack: DialoguePack
    @Published private(set) var uiLocale: String
    private var characterID: String
    private let onReact: (String, String?) -> Void
    private var currentNodeID: String?
    private var transition: DispatchWorkItem?
    private var expressionReset: DispatchWorkItem?
    private var farewellDeadline: DispatchWorkItem?
    private let expressionDuration: TimeInterval

    init(runtime: AppRuntime, pack: DialoguePack, transport: AIChatTransport = AIChatHTTPTransport(), keyProvider: @escaping (String) throws -> String = AIChatKeychain.read, expressionDuration: TimeInterval = 5, onReact: @escaping (String, String?) -> Void) {
        self.expressionDuration = expressionDuration
        self.configuration = runtime.config.aiChat
        self.transport = transport
        self.keyProvider = keyProvider
        self.runtime = runtime
        self.pack = pack
        self.uiLocale = runtime.config.ui.locale
        self.characterID = runtime.config.pet.characterPackId
        self.onReact = onReact
        startFresh()
        memorySubscription = NotificationCenter.default.publisher(for: .aiChatMemoryCleared)
            .sink { [weak self] event in
                guard let self, let store = event.object as? AIChatMemoryStore, store === self.runtime.chatMemory else { return }
                self.sessionHistory = []
                self.lastInput = nil
                self.lastInputTime = nil
                self.startFresh()
            }
    }

    deinit { transition?.cancel(); requestTask?.cancel(); expressionReset?.cancel(); farewellDeadline?.cancel() }

    func synchronize(pack: DialoguePack) {
        uiLocale = runtime.config.ui.locale
        let changed = self.pack != pack || characterID != runtime.config.pet.characterPackId || configuration != runtime.config.aiChat
        self.pack = pack
        configuration = runtime.config.aiChat
        characterID = runtime.config.pet.characterPackId
        if changed { cancel(); sessionHistory = []; draft = ""; localOnlyThisSession = false; startFresh() }
    }

    func ui(_ chinese: String, _ english: String) -> String {
        uiLocale == "en" ? english : InterfaceLanguage.authored(chinese, locale: uiLocale)
    }

    func cancel() {
        generation = UUID()
        expressionReset?.cancel()
        farewellDeadline?.cancel()
        transition?.cancel()
        requestTask?.cancel()
        requestTask = nil
        isBusy = false
    }

    func finishConversation(timeout: TimeInterval = 5, onFarewell: @escaping (String, String?) -> Void) {
        cancel()
        let grass = characterID == "grass-buddy"
        let fallback = grass
            ? t("慢慢来。我在这里，等风，也等你。", "Take your time. I will be here, with the breeze.")
            : [t("……去吧。我替你发会儿呆。", "…Go on. I will do the daydreaming for both of us."),
               t("……下次再聊。我先漂一会儿。", "…Talk later. I will float here for a bit."),
               t("行吧。今天的陪聊，鱼收到了。", "All right. This fish appreciated the company.")].randomElement()!
        let fallbackFace = grass ? "face-grass-calm" : "face-coy"
        guard aiActive, configuration.enabled else { onFarewell(fallback, fallbackFace); return }
        let token = generation
        let config = configuration
        let english = runtime.language?.manifest.locale.hasPrefix("en") == true
        let messages = AIChatPrompt.messages(runtime: runtime, pack: pack, history: sessionHistory, memories: [],
                                            input: t("我要结束这次聊天了，和我道个别吧。", "I am closing this chat. Say a little goodbye."), intent: .farewell)
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.cancel()
            onFarewell(fallback, fallbackFace)
        }
        farewellDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: deadline)
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var text = fallback
            var face: String? = fallbackFace
            do {
                let key = try self.keyProvider(config.endpoint)
                try Task.checkCancellation()
                let content = try await self.transport.complete(configuration: config, key: key, messages: messages)
                let turn = try AIChatTurn.decode(content, english: english)
                if turn.text.count <= (english ? 180 : 60), !turn.text.contains("?"), !turn.text.contains("？") {
                    text = turn.text; face = turn.face(characterID: self.characterID)
                }
            } catch { /* The closing UI stays closed; use the local farewell. */ }
            guard self.generation == token, !Task.isCancelled else { return }
            self.cancel()
            onFarewell(text, face)
        }
    }

    func useLocal() {
        localOnlyThisSession = true
        cancel()
        aiActive = false
        notice = ui("已切换为本地聊天。", "Using local dialogue.")
        renderNode("chat")
    }

    func showGames() {
        cancel()
        aiActive = false
        renderNode("games")
    }

    func rememberLastInput() {
        guard configuration.memoryEnabled, let lastInput else { return }
        do {
            try runtime.chatMemory.remember(lastInput, spokenAt: lastInputTime)
            notice = ui("记住了。可在设置中查看或删除。", "Remembered. View or delete it in Settings.")
        } catch { notice = ui("记忆未能保存，已有数据保持不变。", "Could not save memory. Existing data was preserved.") }
    }

    var showsChoices: Bool { !aiActive || !optionsCollapsed }

    func toggleOptions() {
        guard aiActive else { return }
        optionsCollapsed.toggle()
    }

    func sendDraft() { submit(draft) }

    func openConversation() {
        guard aiActive else { return }
        submit(t("我来陪你待一会儿。", "I am here to spend a little time with you."), intent: .opening)
    }

    func restartConversation() { localOnlyThisSession = false; startFresh(); openConversation() }

    func changeTopic() {
        guard aiActive, !isBusy else { return }
        submit(t("换个轻松的话题，随便聊聊吧。", "Let us talk about something else, just casually."), intent: .newTopic)
    }

    func submit(_ text: String, intent: AIChatTurnIntent = .reply, submittedAt: AIChatTimestamp? = nil) {
        guard aiActive, !isBusy else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.utf8.count <= 4096 else {
            notice = ui("这句有点长，请缩短到 4 KB 以内。", "Please shorten this message to under 4 KB."); return
        }
        transition?.cancel()
        let token = UUID()
        generation = token
        let config = configuration
        let inputTime = submittedAt ?? AIChatTimestamp()
        let submittedDraft = draft
        let sentDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines) == text
        let character = characterID
        let language = runtime.config.language.packId
        let memory = runtime.chatMemory
        let memoryRevision = memory.revision
        let english = runtime.language?.manifest.locale.hasPrefix("en") == true
        var history = sessionHistory
        if config.memoryEnabled && history.isEmpty { history = memory.history(characterID: character, languageID: language) }
        // Include the visible opener so clicking its options has the right context.
        if history.isEmpty { history = [AIChatMessage(role: "assistant", content: prompt, occurredAt: promptTime)] }
        let memories = config.memoryEnabled ? memory.state.facts : []
        let currentPack = pack
        let contextConfig = runtime.config
        let leaseDirectory = runtime.configStore.fileURL.deletingLastPathComponent().appendingPathComponent("agent-task-leases")
        sessionHistory = history
        isBusy = true
        notice = ""
        react(t("……等我想想。", "…Let me think."), face: "face-question")
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let key = try self.keyProvider(config.endpoint)
                try Task.checkCancellation()
                guard self.generation == token else { return }
                let taskContext = await Task.detached(priority: .utility) {
                    AIChatTaskContext.read(directory: leaseDirectory, configuration: contextConfig)
                }.value
                try Task.checkCancellation()
                guard self.generation == token else { return }
                var requestMessages = AIChatPrompt.messages(runtime: self.runtime, pack: currentPack, history: history,
                                                           memories: memories, input: text, intent: intent, inputTime: inputTime, taskContext: taskContext)
                var result: AIChatTurn?
                for attempt in 0..<2 {
                    if !AIChatTaskContext.isEnabled(self.runtime.config)
                        || self.runtime.config.privacy != contextConfig.privacy
                        || self.runtime.config.integrations != contextConfig.integrations {
                        requestMessages.removeAll { $0.content == taskContext }
                    }
                    let content = try await self.transport.complete(configuration: config, key: key, messages: requestMessages)
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    do { result = try AIChatTurn.decode(content, english: english); break }
                    catch {
                        guard attempt == 0 else { throw AIChatError.response }
                        requestMessages.append(AIChatMessage(role: "user", content: "Return a corrected JSON response to my last message. Follow the original length, options and emotion constraints exactly."))
                    }
                }
                guard let result, self.generation == token else { return }
                self.isBusy = false
                if intent == .reply { self.lastInput = text; self.lastInputTime = inputTime }
                if intent == .reply && sentDraft && self.draft == submittedDraft { self.draft = "" }
                let replyTime = AIChatTimestamp()
                let exchange = intent != .reply ? [AIChatMessage(role: "assistant", content: result.text, occurredAt: replyTime)]
                    : [AIChatMessage(role: "user", content: text, occurredAt: inputTime), AIChatMessage(role: "assistant", content: result.text, occurredAt: replyTime)]
                self.sessionHistory = Array((history + exchange).suffix(12))
                if intent == .reply && config.memoryEnabled && memory.revision == memoryRevision {
                    do {
                        try memory.record(user: text, fish: result.text, characterID: character, languageID: language, userTime: inputTime, fishTime: replyTime)
                        let prefixes = ["记住", "記住", "请记住", "請記住", "remember ", "please remember "]
                        if prefixes.contains(where: { text.lowercased().hasPrefix($0) }) { try memory.remember(text, spokenAt: inputTime) }
                    } catch { self.notice = self.ui("这次记忆未能保存。", "This conversation could not be saved.") }
                }
                self.react(result.text, face: result.face(characterID: character))
                self.choices = result.options.map { label in
                    Choice(label: label) { [weak self] in self?.submit(label) }
                }
            } catch {
                guard self.generation == token, !Task.isCancelled else { return }
                self.isBusy = false
                if intent == .reply && self.draft.isEmpty && self.draft == submittedDraft { self.draft = text }
                self.notice = (error as? AIChatError).map { InterfaceLanguage.authored($0.message(english: self.uiLocale == "en"), locale: self.uiLocale) }
                    ?? self.ui("连接超时或不可用。可以重试，也可以继续本地聊天。", "Connection unavailable or timed out. Retry or continue locally.")
                self.react(self.t("……这句没接住。我还在。", "…Lost that thought. I'm still here."), face: "face-doubt")
                self.choices = [
                    Choice(label: self.ui("再试一次", "Try again")) { [weak self] in self?.submit(text, intent: intent, submittedAt: inputTime) },
                    Choice(label: self.ui("继续本地聊天", "Continue locally")) { [weak self] in self?.useLocal() }
                ]
            }
        }
    }

    private func t(_ chinese: String, _ english: String) -> String { runtime.speechText(chinese, english) }

    func startFresh() {
        cancel()
        aiActive = configuration.enabled && !localOnlyThisSession
        notice = ""
        transition?.cancel()
        moodFaceID = nil
        let openers = pack.nodes.filter { $0.value.opener == true }.map(\.key).sorted()
        guard let id = openers.randomElement() else { prompt = "……"; choices = []; return }
        renderNode(id)
    }

    private func renderNode(_ id: String) {
        guard let node = pack.nodes[id] else { startFresh(); return }
        currentNodeID = id
        react(node.prompt, face: "face-blank")
        choices = node.options.enumerated().map { index, option in
            Choice(label: option.label) { [weak self] in
                guard let self else { return }
                if self.aiActive { self.submit(option.label) } else { self.choose(index) }
            }
        }
    }

    private func choose(_ index: Int) {
        guard let id = currentNodeID, let node = pack.nodes[id], node.options.indices.contains(index) else { return }
        let option = node.options[index]
        let readingDelay = max(1.8, min(6, Double(option.reply?.count ?? 0) * 0.12))
        choices = []
        if let reply = option.reply { react(reply, face: option.face) }
        else if let face = option.face { moodFaceID = face; onReact("", face) }
        if let game = option.game {
            schedule(after: option.reply == nil ? 0.35 : readingDelay) { [weak self] in self?.runGame(game) }
        } else if let next = option.next {
            schedule(after: option.reply == nil ? 0.2 : readingDelay) { [weak self] in self?.renderNode(next) }
        } else {
            schedule(after: readingDelay) { [weak self] in self?.startFresh() }
        }
    }

    private func react(_ text: String, face: String?) {
        prompt = text
        promptTime = AIChatTimestamp()
        let compatibleFace: String?
        if characterID == "grass-buddy", let face, !face.hasPrefix("face-grass-") {
            compatibleFace = ["face-proud", "face-star-eye", "face-smug", "face-satisfied"].contains(face)
                ? "face-grass-happy" : "face-grass-calm"
        } else { compatibleFace = face }
        moodFaceID = compatibleFace
        onReact(text, compatibleFace)
        expressionReset?.cancel()
        guard compatibleFace != nil else { return }
        let reset = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.moodFaceID = nil
            // Keep the current words and original timestamp; only relax the face.
            self.onReact(self.prompt, nil)
        }
        expressionReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + expressionDuration, execute: reset)
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        transition?.cancel()
        let item = DispatchWorkItem(block: action)
        transition = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func runGame(_ id: String) {
        currentNodeID = nil
        switch id {
        case "rps": playRPS()
        case "dice": playDice()
        case "riddle": playRiddle()
        default: startFresh()
        }
    }

    private func afterRound(replay: @escaping () -> Void) {
        choices = [
            Choice(label: t("再来一局", "Play again"), action: replay),
            Choice(label: t("换个游戏", "Another game")) { [weak self] in self?.renderNode("games") },
            Choice(label: t("不玩了", "Back to chatting")) { [weak self] in self?.startFresh() },
        ]
    }

    private func playRPS() {
        react(t("选一个吧。慢慢来。", "Choose one. Take your time."), face: "face-question")
        let moves = [(t("✊ 石头", "✊ Rock"), 0), (t("✌️ 剪刀", "✌️ Scissors"), 1), (t("🖐 布", "🖐 Paper"), 2)]
        choices = moves.map { label, move in
            Choice(label: label) { [weak self] in self?.finishRPS(player: move) }
        }
    }

    private func finishRPS(player: Int) {
        let fish = Int.random(in: 0..<3)
        let names = [t("石头", "rock"), t("剪刀", "scissors"), t("布", "paper")]
        let playerWon = (player == 0 && fish == 1) || (player == 1 && fish == 2) || (player == 2 && fish == 0)
        let text: String
        let face: String
        if player == fish { text = t("我出\(names[fish])。……想到一块去了。", "I chose \(names[fish]). …Same idea."); face = "face-side-eye" }
        else if playerWon { text = t("我出\(names[fish])。这局你赢了。", "I chose \(names[fish]). You won this round."); face = "face-annoyed" }
        else { text = t("我出\(names[fish])。这局是我赢了。", "I chose \(names[fish]). This round is mine."); face = "face-proud" }
        react(text, face: face)
        afterRound { [weak self] in self?.playRPS() }
    }

    private func playDice() {
        react(t("猜大小。两颗骰子，七点算我赢。", "Guess the total of two dice. Seven is my win."), face: "face-question")
        choices = [
            Choice(label: t("大（8–12）", "Big (8–12)")) { [weak self] in self?.finishDice(bet: "big") },
            Choice(label: t("小（2–6）", "Small (2–6)")) { [weak self] in self?.finishDice(bet: "small") },
        ]
    }

    private func finishDice(bet: String) {
        let dice = [Int.random(in: 1...6), Int.random(in: 1...6)]
        let total = dice[0] + dice[1]
        let size = total <= 6 ? "small" : total >= 8 ? "big" : "seven"
        let won = size == bet
        let reply = size == "seven" ? t("七点，这局归我。", "Seven. This round is mine.") : won ? t("……猜中了。", "…You guessed it.") : t("没猜中。下次再试。", "Not this time. Try again.")
        react("🎲 \(dice[0]) + \(dice[1]) = \(total). \(reply)", face: size == "seven" ? "face-teasing" : won ? "face-shocked" : "face-smug")
        afterRound { [weak self] in self?.playDice() }
    }

    private struct Riddle {
        let question: String; let options: [String]; let answer: Int; let reveal: String
    }

    private func playRiddle() {
        let riddles = [
            Riddle(question: t("什么有很多齿，却不能咬东西？", "What has teeth but cannot bite?"), options: [t("梳子", "A comb"), t("猫", "A cat"), t("鱼", "A fish")], answer: 0, reveal: t("梳子。那些齿只会梳头。", "A comb. Its teeth only tidy hair.")),
            Riddle(question: t("什么东西越洗越脏？", "What gets dirtier as it washes things?"), options: [t("衣服", "Clothes"), t("水", "Water"), t("碗", "A bowl")], answer: 1, reveal: t("水。洗什么都把自己弄脏。", "Water. It collects the dirt.")),
            Riddle(question: t("平年的哪個月天數最少？", "Which month has the fewest days in a common year?"), options: [t("二月", "February"), t("十二月", "December"), t("六月", "June")], answer: 0, reveal: t("二月，只有二十八天。", "February, with only twenty-eight days.")),
            Riddle(question: t("什么越擦越湿？", "What gets wetter as it dries things?"), options: [t("阳光", "Sunlight"), t("毛巾", "A towel"), t("风", "The wind")], answer: 1, reveal: t("毛巾。水都留在它身上了。", "A towel. It holds the water.")),
        ]
        let riddle = riddles.randomElement()!
        react(riddle.question, face: "face-question")
        choices = riddle.options.enumerated().map { index, label in
            Choice(label: label) { [weak self] in self?.finishRiddle(riddle, choice: index) }
        }
    }

    private func finishRiddle(_ riddle: Riddle, choice: Int) {
        let correct = choice == riddle.answer
        react(correct ? t("……答对了。", "…That's right.") : t("不对。", "Not quite. ") + riddle.reveal, face: correct ? "face-star-eye" : "face-teasing")
        afterRound { [weak self] in self?.playRiddle() }
    }
}

struct DialogueView: View {
    @ObservedObject var model: DialogueViewModel
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var fill: Color { colorScheme == .dark ? Color(red: 0.24, green: 0.17, blue: 0.21) : Color(red: 1, green: 0.94, blue: 0.96) }

    private var toolFill: Color { colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.98) }
    private var menuEntries: [DialogueMoreControl.Entry] {
        var entries: [DialogueMoreControl.Entry] = []
        if model.aiActive {
            entries += [
                .init(title: model.ui("换个话题", "Surprise me"), enabled: !model.isBusy) { model.changeTopic() }
            ]
        }
        entries += [
            .init(title: model.ui("玩个小游戏", "Play a game")) { model.showGames() },
            .init(title: model.ui("重新聊聊", "Start again")) { model.restartConversation() }
        ]
        if model.runtime.config.aiChat.memoryEnabled {
            entries.append(.init(title: model.ui("记住我刚才说的话", "Remember my last message")) { model.rememberLastInput() })
        }
        return entries
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if model.isBusy {
                    ProgressView().controlSize(.small)
                    Text(model.ui("想一想……", "Thinking…")).font(.caption)
                    Button(model.ui("取消", "Cancel")) { model.useLocal() }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    if model.aiActive {
                        Button(action: model.toggleOptions) {
                            Image(systemName: model.optionsCollapsed ? "chevron.down" : "chevron.up")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 28, height: 24).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(model.optionsCollapsed ? model.ui("展开回复选项", "Show reply options") : model.ui("收起选项，只打字回复", "Hide options and type replies"))
                        .accessibilityLabel(model.ui("回复选项", "Reply options"))
                        .accessibilityValue(model.optionsCollapsed ? model.ui("已收起", "Collapsed") : model.ui("已展开", "Expanded"))
                        Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 12)
                    }
                    DialogueMoreControl(label: model.ui("更多选项", "More options"), entries: menuEntries)
                        .frame(width: 28, height: 24)
                    Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 12)
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                            .frame(width: 28, height: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help(model.ui("收起聊天（Esc）", "Close chat (Esc)"))
                    .accessibilityLabel(model.ui("收起聊天", "Close chat"))
                }
                .background(toolFill, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.18), lineWidth: 0.75))
            }
            .foregroundStyle(.primary).frame(height: 24)
            if model.showsChoices {
                ForEach(model.choices) { choice in
                    Button(action: choice.action) {
                        Text(choice.label).font(.system(size: 12)).lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .padding(.horizontal, 8)
                            .background(fill, in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.pink.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain).disabled(model.isBusy)
                }
            }
            if model.aiActive {
                HStack(spacing: 8) {
                    FishComposeEditor(text: $model.draft, ink: .labelColor,
                                      placeholder: model.ui("自己说点什么……", "Say something…"),
                                      placeholderColor: .placeholderTextColor,
                                      accessibilityLabel: model.ui("和鱼聊天", "Chat with your pet"), onSend: model.sendDraft, fontSize: 12)
                        .frame(height: 32).padding(.horizontal, 6)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
                    Button(action: model.sendDraft) {
                        Image(systemName: "arrow.up").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white).frame(width: 28, height: 28).background(Color.pink, in: Circle())
                    }
                    .buttonStyle(.plain).disabled(model.isBusy || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(model.ui("发送（回车）；⌘ 回车换行", "Send (Return); ⌘ Return for a new line"))
                }
            }
            if !model.notice.isEmpty {
                Text(model.notice).font(.caption).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    .padding(6).frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(4)
        .frame(width: DialogueLayout.width)
        // No shared background: only each option and the editor have a surface.
    }
}

// Use an image-only AppKit button: SwiftUI's macOS Menu reserves asymmetric
// arrow/cell padding even with menuIndicator(.hidden), shifting the ellipsis.
struct DialogueMoreControl: NSViewRepresentable {
    struct Entry {
        let title: String
        var enabled = true
        let action: () -> Void
    }
    let label: String
    let entries: [Entry]
    final class Control: NSButton {
        // Remove AppKit's bezel alignment compensation in the borderless slot.
        override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
        override var intrinsicContentSize: NSSize { NSSize(width: 28, height: 24) }
        var entries: [Entry] = []
        @objc func showActions() {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for (index, entry) in entries.enumerated() {
                let item = NSMenuItem(title: entry.title, action: #selector(invoke(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.isEnabled = entry.enabled
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY + 3), in: self)
        }
        @objc private func invoke(_ sender: NSMenuItem) {
            guard entries.indices.contains(sender.tag), entries[sender.tag].enabled else { return }
            entries[sender.tag].action()
        }
    }
    func makeNSView(context: Context) -> Control {
        let button = Control(frame: .zero)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        button.contentTintColor = .labelColor
        button.target = button
        button.action = #selector(Control.showActions)
        return button
    }
    func updateNSView(_ button: Control, context: Context) {
        button.entries = entries
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }
}

enum DialogueLayout {
    static let width: CGFloat = 248
    static func frame(size: CGSize, anchor: PetSceneAnchor) -> CGRect {
        let visible = anchor.visibleFrame.insetBy(dx: 8, dy: 8)
        return CGRect(x: min(max(anchor.primaryFrame.midX - size.width / 2, visible.minX), visible.maxX - size.width),
                      y: max(visible.minY, anchor.formationFrame.minY - 10 - size.height),
                      width: size.width, height: size.height)
    }
    static func lift(size: CGSize, anchor: PetSceneAnchor) -> CGFloat {
        let required = anchor.visibleFrame.minY + 8 + size.height + 10 - anchor.formationFrame.minY
        return max(0, min(required, anchor.visibleFrame.maxY - 100 - anchor.formationFrame.maxY))
    }
}

final class DialoguePanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { if let onDismiss { onDismiss() } else { close() } }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelOperation(nil) } else { super.keyDown(with: event) }
    }
}

@MainActor
final class DialogueWindowController: NSWindowController, NSWindowDelegate {
    private let model: DialogueViewModel
    private var anchor: PetSceneAnchor?
    private var subscription: AnyCancellable?
    var onClose: (() -> Void)?
    var onFarewell: ((String, String?) -> Void)?
    private var farewellRequested = false
    var reserveSpace: ((CGSize) -> PetSceneAnchor?)?
    private var positioning = false
    private var opened = false

    init(runtime: AppRuntime, pack: DialoguePack, onReact: @escaping (String, String?) -> Void) {
        let model = DialogueViewModel(runtime: runtime, pack: pack, onReact: onReact)
        self.model = model
        let panel = DialoguePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.contentView = NSHostingView(rootView: DialogueView(model: model) { [weak self] in self?.closeFromUser() })
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onDismiss = { [weak self] in self?.closeFromUser() }
        subscription = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.reposition() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(anchor: PetSceneAnchor?) {
        self.anchor = anchor
        reposition(allowHidden: true)
        window?.makeKeyAndOrderFront(nil)
        if !opened { opened = true; model.openConversation() }
    }

    func updateAnchor(_ anchor: PetSceneAnchor) {
        self.anchor = anchor
        if window?.isVisible == true { reposition() }
    }

    private func reposition(allowHidden: Bool = false) {
        guard !positioning, let window, allowHidden || window.isVisible, let view = window.contentView else { return }
        positioning = true
        defer { positioning = false }
        view.layoutSubtreeIfNeeded()
        let size = NSSize(width: DialogueLayout.width, height: max(40, view.fittingSize.height))
        if let next = reserveSpace?(size) { anchor = next }
        guard let anchor else { return }
        window.setFrame(DialogueLayout.frame(size: size, anchor: anchor), display: true)
    }

    private func closeFromUser() {
        farewellRequested = true
        close()
    }

    func cancelPendingResponses() { model.cancel() }

    func windowWillClose(_ notification: Notification) {
        model.cancel()
        onClose?()
        if farewellRequested, let onFarewell { model.finishConversation(onFarewell: onFarewell) }
        farewellRequested = false
    }

    func synchronize(pack: DialoguePack) { model.synchronize(pack: pack) }
}
