#if DEBUG
import AppKit

// An isolated UI harness. Never starts pet services or reads real conversations.
@MainActor enum CodexQuestionPreview {
    static func run(output: URL) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = CodexQuestionWindowController()
        let options = [
            CodexQuestion.Option(label: "保持当前行为（推荐）", description: "保留人工确认，自动审核期间继续工作。"),
            CodexQuestion.Option(label: "开启问题预览", description: "将原题和选项递到桌面，仍回 Codex 回答。"),
            CodexQuestion.Option(label: "暂时关闭", description: "关闭后停止采集问题正文，不影响审批提醒。")
        ]
        let request = CodexQuestionRequest(id: "preview", threadID: "preview-thread", turnID: "preview-turn", blocking: false, questions: [
            .init(id: "1", title: "有多个 Codex 任务同时运行时，你希望水滴鱼怎样提醒需要人工确认的任务？", options: options),
            .init(id: "2", title: "是否还有其他使用习惯，需要水滴鱼一起照顾？", options: [])
        ])
        controller.synchronize([request], locale: "zh-CN", anchor: nil)
        controller.window?.center()
        controller.window?.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                for (name, appearance, english) in [("light", NSAppearance.Name.aqua, false), ("dark", NSAppearance.Name.darkAqua, false), ("english", NSAppearance.Name.aqua, true)] {
                    controller.window?.appearance = NSAppearance(named: appearance)
                    controller.model.locale = english ? "en" : "zh-CN"
                    if english {
                        controller.model.synchronize([.init(id: "en", threadID: "preview-thread", turnID: "preview-turn", blocking: true, questions: [
                            .init(id: "1", title: "When several Codex tasks are running, how should the fish bring questions to your attention?", options: [
                                .init(label: "Keep human approvals visible (Recommended)", description: "Automatic reviews keep working; real approval requests still notify you."),
                                .init(label: "Preview questions beside the fish", description: "Read each question here, then return to its Codex task to answer.")])])])
                    }
                    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                    guard let view = controller.window?.contentView else { continue }
                    view.layoutSubtreeIfNeeded()
                    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: output.appendingPathComponent(name + ".png")) }
                }
                controller.synchronize([request], locale: "zh-CN", anchor: nil)
                controller.model.index = 1
                precondition(controller.model.page?.question.options.isEmpty == true)
                controller.window?.performClose(nil)
                controller.synchronize([request], locale: "zh-CN", anchor: nil)
                precondition(controller.window?.isVisible == false, "Polling must not reopen dismissed questions")
                controller.synchronize([], locale: "zh-CN", anchor: nil)
                precondition(controller.model.pages.isEmpty && controller.window?.isVisible == false)
                print("Question previews saved: \(output.path)")
            } catch { print("Question preview failed: \(error)") }
            controller.close()
            fflush(stdout)
            Darwin.exit(0)
        }
        app.run()
        withExtendedLifetime(controller) {}
    }
}
#endif
