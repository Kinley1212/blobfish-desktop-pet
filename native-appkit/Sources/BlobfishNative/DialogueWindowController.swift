import AppKit
import SwiftUI

@MainActor
final class DialogueViewModel: ObservableObject {
    struct Choice: Identifiable {
        let id = UUID()
        let label: String
        let action: () -> Void
    }

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

    init(runtime: AppRuntime, pack: DialoguePack, onReact: @escaping (String, String?) -> Void) {
        self.runtime = runtime
        self.pack = pack
        self.uiLocale = runtime.config.ui.locale
        self.characterID = runtime.config.pet.characterPackId
        self.onReact = onReact
        startFresh()
    }

    deinit { transition?.cancel() }

    func synchronize(pack: DialoguePack) {
        uiLocale = runtime.config.ui.locale
        let changed = self.pack != pack || characterID != runtime.config.pet.characterPackId
        self.pack = pack
        characterID = runtime.config.pet.characterPackId
        if changed { startFresh() }
    }

    private func t(_ chinese: String, _ english: String) -> String { runtime.speechText(chinese, english) }

    func startFresh() {
        transition?.cancel()
        moodFaceID = nil
        let openers = pack.nodes.filter { $0.value.opener == true }.map(\.key).sorted()
        guard let id = openers.randomElement() else { prompt = "……"; choices = []; return }
        renderNode(id)
    }

    private func renderNode(_ id: String) {
        guard let node = pack.nodes[id] else { startFresh(); return }
        currentNodeID = id
        prompt = node.prompt
        choices = node.options.enumerated().map { index, option in
            Choice(label: option.label) { [weak self] in self?.choose(index) }
        }
    }

    private func choose(_ index: Int) {
        guard let id = currentNodeID, let node = pack.nodes[id], node.options.indices.contains(index) else { return }
        let option = node.options[index]
        choices = []
        if let reply = option.reply { react(reply, face: option.face) }
        else if let face = option.face { moodFaceID = face; onReact("", face) }
        if let game = option.game {
            schedule(after: option.reply == nil ? 0.35 : 0.7) { [weak self] in self?.runGame(game) }
        } else if let next = option.next {
            schedule(after: option.reply == nil ? 0.2 : 0.95) { [weak self] in self?.renderNode(next) }
        } else {
            schedule(after: 1.4) { [weak self] in self?.startFresh() }
        }
    }

    private func react(_ text: String, face: String?) {
        prompt = text
        let compatibleFace: String?
        if characterID == "grass-buddy", let face, !face.hasPrefix("face-grass-") {
            compatibleFace = ["face-proud", "face-star-eye", "face-smug", "face-satisfied"].contains(face)
                ? "face-grass-happy" : "face-grass-calm"
        } else { compatibleFace = face }
        moodFaceID = compatibleFace
        onReact(text, compatibleFace)
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
        prompt = t("选一个吧。慢慢来。", "Choose one. Take your time.")
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
        prompt = t("猜大小。两颗骰子，七点算我赢。", "Guess the total of two dice. Seven is my win.")
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
        prompt = riddle.question
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

    private var character: CharacterPack? { model.runtime.character }
    private var spec: CharacterAccessories {
        AppearanceJSON.accessorySpec(in: model.runtime.config, characterID: model.runtime.config.pet.characterPackId)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(model.uiLocale == "en" ? "Chat with your pet" : "和桌宠聊聊")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).padding(5)
                    .background(Color.pink.opacity(0.14), in: Circle())
            }
            HStack(alignment: .bottom, spacing: 10) {
                PetAppearancePreview(
                    character: character,
                    scale: 0.9,
                    accessories: model.runtime.accessories,
                    accessorySpec: spec,
                    customization: model.runtime.config.pet.customization[model.runtime.config.pet.characterPackId],
                    moodFaceID: model.moodFaceID
                )
                .frame(width: 104, height: 96)
                Text(model.prompt)
                    .font(.system(size: 15)).lineSpacing(3)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(12)
                    .background(Color.pink.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
            }
            VStack(spacing: 8) {
                ForEach(model.choices) { choice in
                    Button(action: choice.action) {
                        Text(choice.label).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 320, height: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

@MainActor
final class DialogueWindowController: NSWindowController {
    private let model: DialogueViewModel
    init(runtime: AppRuntime, pack: DialoguePack, onReact: @escaping (String, String?) -> Void) {
        let model = DialogueViewModel(runtime: runtime, pack: pack, onReact: onReact)
        self.model = model
        var window: NSWindow!
        let hosting = NSHostingController(rootView: DialogueView(model: model) { window.close() })
        window = NSWindow(contentViewController: hosting)
        window.title = runtime.config.ui.locale == "en" ? "Chat with your pet" : "和桌宠聊天"
        window.styleMask = [.titled, .closable]
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 320, height: 340))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func synchronize(pack: DialoguePack) {
        model.synchronize(pack: pack)
        window?.title = model.uiLocale == "en" ? "Chat with your pet" : "和桌宠聊天"
    }
}
