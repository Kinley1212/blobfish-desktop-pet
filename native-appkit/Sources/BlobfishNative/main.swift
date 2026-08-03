import AppKit
import Darwin

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
