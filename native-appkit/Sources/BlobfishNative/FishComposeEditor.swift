import AppKit
import SwiftUI

enum FishComposeReturnAction {
    case system, send, newline, consume

    static func resolve(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                        hasMarkedText: Bool, isRepeat: Bool) -> Self {
        guard [36, 76].contains(keyCode), !hasMarkedText else { return .system }
        let keys = modifiers.intersection([.command, .shift, .option, .control])
        if keys == .command { return .newline }
        if keys.isEmpty { return isRepeat ? .consume : .send }
        return .system
    }
}

final class FishComposeTextView: NSTextView {
    var onSend: () -> Void = {}

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.initialFirstResponder = self
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.isKeyWindow else { return }
            window.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if !handleReturn(event) { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Command shortcuts are dispatched before keyDown. Only this editor,
        // while focused, owns Command-Return; menus and other fields keep theirs.
        if window?.firstResponder === self,
           event.modifierFlags.contains(.command), handleReturn(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func handleReturn(_ event: NSEvent) -> Bool {
        switch FishComposeReturnAction.resolve(
            keyCode: event.keyCode, modifiers: event.modifierFlags,
            hasMarkedText: hasMarkedText(), isRepeat: event.isARepeat
        ) {
        case .system: return false // Let the input method confirm its candidate.
        case .send: onSend()
        case .newline: insertNewline(nil)
        case .consume: break // Holding Return must not repeatedly submit.
        }
        return true
    }
}

struct FishComposeEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.isEnabled) private var isEnabled
    let ink: NSColor
    let accessibilityLabel: String
    let onSend: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let editor = FishComposeTextView(frame: NSRect(x: 0, y: 0, width: 224, height: 58))
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 13)
        editor.textContainerInset = NSSize(width: 0, height: 8)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 224, height: CGFloat.greatestFiniteMagnitude)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.allowsUndo = true
        editor.delegate = context.coordinator
        editor.string = text
        scroll.documentView = editor
        configure(editor)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? FishComposeTextView else { return }
        configure(editor)
        // Incoming UI updates must not reset selection, undo or IME composition.
        if editor.string != text, !editor.hasMarkedText() {
            editor.string = text
            editor.undoManager?.removeAllActions()
        }
    }

    private func configure(_ editor: FishComposeTextView) {
        editor.isEditable = isEnabled
        editor.textColor = ink
        editor.insertionPointColor = ink
        editor.setAccessibilityLabel(accessibilityLabel)
        editor.onSend = onSend
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let editor = scroll.documentView as? FishComposeTextView else { return }
        editor.delegate = nil
        editor.onSend = {}
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FishComposeEditor
        init(_ parent: FishComposeEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}
