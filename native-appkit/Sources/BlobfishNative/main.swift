import AppKit
import Darwin

#if DEBUG
if let index = CommandLine.arguments.firstIndex(of: "--codex-question-preview"), CommandLine.arguments.indices.contains(index + 1) {
    MainActor.assumeIsolated { CodexQuestionPreview.run(output: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
    Darwin.exit(0)
}
#endif

if CommandLine.arguments.contains("--self-test") {
    Darwin.exit(SelfCheck.run() ? 0 : 1)
} else {
    let openSettingsAtLaunch = CommandLine.arguments.contains("--open-settings")
    let application = NSApplication.shared
    let delegate = AppDelegate(openSettingsAtLaunch: openSettingsAtLaunch)
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
    withExtendedLifetime(delegate) {}
}
