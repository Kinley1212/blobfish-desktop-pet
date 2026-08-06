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
    private let pack: DialoguePack
    private let onReact: (String, String?) -> Void
    private var currentNodeID: String?
    private var transition: DispatchWorkItem?

    init(runtime: AppRuntime, pack: DialoguePack, onReact: @escaping (String, String?) -> Void) {
        self.runtime = runtime
        self.pack = pack
        self.onReact = onReact
        startFresh()
    }

    deinit { transition?.cancel() }

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
        moodFaceID = face
        onReact(text, face)
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
            Choice(label: "再来一局", action: replay),
            Choice(label: "换个游戏") { [weak self] in self?.renderNode("games") },
            Choice(label: "不玩了") { [weak self] in self?.startFresh() },
        ]
    }

    private func playRPS() {
        prompt = "出什么？输了不许哭。"
        let moves = [("✊ 石头", 0), ("✌️ 剪刀", 1), ("🖐 布", 2)]
        choices = moves.map { label, move in
            Choice(label: label) { [weak self] in self?.finishRPS(player: move) }
        }
    }

    private func finishRPS(player: Int) {
        let fish = Int.random(in: 0..<3)
        let names = ["石头", "剪刀", "布"]
        let playerWon = (player == 0 && fish == 1) || (player == 1 && fish == 2) || (player == 2 && fish == 0)
        let text: String
        let face: String
        if player == fish { text = "我出\(names[fish])。……想到一块去了。"; face = "face-side-eye" }
        else if playerWon { text = "我出\(names[fish])。……哼，让你了。"; face = "face-annoyed" }
        else { text = "我出\(names[fish])。嘿，我赢了。"; face = "face-proud" }
        react(text, face: face)
        afterRound { [weak self] in self?.playRPS() }
    }

    private func playDice() {
        prompt = "猜大小。骰子要摇了。"
        choices = [
            Choice(label: "压大（8-11）") { [weak self] in self?.finishDice(bet: "big") },
            Choice(label: "压小（3-6）") { [weak self] in self?.finishDice(bet: "small") },
        ]
    }

    private func finishDice(bet: String) {
        let dice = [Int.random(in: 1...6), Int.random(in: 1...6)]
        let total = dice[0] + dice[1]
        let size = total <= 6 ? "small" : total >= 8 ? "big" : "seven"
        let won = size == bet
        let reply = size == "seven" ? "七点，归我。运气不好吧你。" : won ? "……真让你猜中了。" : "猜错咯～"
        react("🎲 \(dice[0]) + \(dice[1]) = \(total)。\(reply)", face: size == "seven" ? "face-teasing" : won ? "face-shocked" : "face-smug")
        afterRound { [weak self] in self?.playDice() }
    }

    private struct Riddle {
        let question: String; let options: [String]; let answer: Int; let reveal: String
    }

    private func playRiddle() {
        let riddles = [
            Riddle(question: "什么鱼没有骨头，还整天摆臭脸？", options: ["金鱼", "水滴鱼", "章鱼"], answer: 1, reveal: "……说的就是我。谢谢。"),
            Riddle(question: "什么东西越洗越脏？", options: ["衣服", "水", "碗"], answer: 1, reveal: "水。洗什么都把自己弄脏。"),
            Riddle(question: "一年里哪个月睡得最少？", options: ["二月", "十二月", "看心情"], answer: 0, reveal: "二月呀，天数最少。"),
            Riddle(question: "什么帽子摘不下来？", options: ["安全帽", "瓶盖", "螺丝帽"], answer: 2, reveal: "螺丝帽。你试试摘。"),
        ]
        let riddle = riddles.randomElement()!
        prompt = riddle.question
        choices = riddle.options.enumerated().map { index, label in
            Choice(label: label) { [weak self] in self?.finishRiddle(riddle, choice: index) }
        }
    }

    private func finishRiddle(_ riddle: Riddle, choice: Int) {
        let correct = choice == riddle.answer
        react(correct ? "……居然答对了。" : "不对。\(riddle.reveal)", face: correct ? "face-star-eye" : "face-teasing")
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
                Text(model.runtime.config.ui.locale == "en" ? "Chat with your pet" : "和水滴鱼聊聊")
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
    init(runtime: AppRuntime, pack: DialoguePack, onReact: @escaping (String, String?) -> Void) {
        let model = DialogueViewModel(runtime: runtime, pack: pack, onReact: onReact)
        var window: NSWindow!
        let hosting = NSHostingController(rootView: DialogueView(model: model) { window.close() })
        window = NSWindow(contentViewController: hosting)
        window.title = runtime.config.ui.locale == "en" ? "Chat with your pet" : "和水滴鱼聊天"
        window.styleMask = [.titled, .closable]
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 320, height: 340))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
