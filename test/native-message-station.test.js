const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..', 'native-appkit', 'Sources', 'BlobfishNative');
const controller = fs.readFileSync(path.join(root, 'FishChatWindowController.swift'), 'utf8');
const app = fs.readFileSync(path.join(root, 'AppDelegate.swift'), 'utf8');
const view = fs.readFileSync(path.join(root, 'FishMessageStationView.swift'), 'utf8');

test('message panels establish non-activation and fullscreen behavior at construction', () => {
  const panel = controller.slice(controller.indexOf('final class FishMessagePanel'), controller.indexOf('enum FishChatDraftPolicy'));
  assert.match(panel, /: NSPanel/);
  assert.match(panel, /var style: NSWindow.StyleMask = \[\.titled, \.closable, \.nonactivatingPanel\]/);
  assert.match(panel, /super.init\(contentRect: \.zero, styleMask: style/);
  assert.match(panel, /collectionBehavior = \[\.canJoinAllSpaces, \.fullScreenAuxiliary\]/);
  assert.match(panel, /canBecomeKey: Bool \{ true \}/);
  assert.match(panel, /canBecomeMain: Bool \{ false \}/);
  assert.match(panel, /hidesOnDeactivate = false/);
  assert.equal((controller.match(/FishMessagePanel\(hosting:/g) || []).length, 2);
});

test('message entry points never activate the entire application', () => {
  const routes = app.slice(app.indexOf('private func openFishHistory('), app.indexOf('private func presentSentFishMessage('));
  assert.ok(routes.includes('showHistory'));
  assert.ok(routes.includes('showComposer'));
  assert.doesNotMatch(routes, /NSApp.activate|activateIgnoringOtherApps/);
  const show = controller.slice(controller.indexOf('func showComposer('), controller.indexOf('func updateSceneAnchor('));
  assert.ok(show.indexOf('reposition(force: true)') < show.indexOf('makeKeyAndOrderFront'));
  assert.match(show, /windowDidBecomeKey[\s\S]*?setPresented\(true\)/);
  assert.match(show, /windowDidResignKey[\s\S]*?setPresented\(false\)/);
});

test('stationery editor is multiline and guards IME composition before sending', () => {
  assert.match(view, /FishComposeEditor\(text: \$model.draft/);
  assert.doesNotMatch(view, /keyboardShortcut\(\.return/);
  assert.match(view, /editor.hasMarkedText\(\) \{ return \}[\s\S]*?model.sendMessage\(\)/);
  assert.doesNotMatch(view, /onSubmit|makeFirstResponder\(nil\)/);
  assert.match(view, /disabled\(model.sendDisabled\)/);
});

test('both message inputs delegate placeholder visibility to the native IME buffer', () => {
  const editor = fs.readFileSync(path.join(root, 'FishComposeEditor.swift'), 'utf8');
  assert.match(editor, /var shouldShowPlaceholder: Bool \{ string.isEmpty && !hasMarkedText\(\) \}/);
  assert.match(editor, /guard shouldShowPlaceholder else \{ return \}/);
  for (const input of [view, controller]) {
    assert.match(input, /FishComposeEditor\(text: \$model.draft, ink:[\s\S]*?placeholder:/);
    assert.doesNotMatch(input, /if model.draft.isEmpty \{\s*Text\(/);
  }
  assert.match(editor, /override func setMarkedText\([\s\S]*?super.setMarkedText\([\s\S]*?needsDisplay = true/);
  assert.match(editor, /override func unmarkText\(\)[\s\S]*?super.unmarkText\(\)[\s\S]*?needsDisplay = true/);
  assert.match(editor, /override func didChangeText\(\)[\s\S]*?super.didChangeText\(\)[\s\S]*?needsDisplay = true/);
  assert.match(editor, /if editor.string != text, !editor.hasMarkedText\(\) \{[\s\S]*?editor.string = text[\s\S]*?editor.needsDisplay = true/);
});

test('stationery pairs paper and ink in both appearances without outlined art', () => {
  for (const token of ['backdrop', 'paper', 'ink', 'muted']) {
    assert.match(view, new RegExp('var ' + token + ': Color \\{ dark \\?'));
  }
  assert.match(view, /colorScheme == \.dark/);
  assert.doesNotMatch(view, /\.stroke\(|\.strokeBorder\(/);
});

test('visit doorplate remains separate from the three shortcuts and expandable interactions', () => {
  const recipient = view.slice(view.indexOf('private var recipient:'), view.indexOf('private var visitButton:'));
  assert.match(recipient, /ForEach\(model.quickInteractions\)/);
  assert.doesNotMatch(recipient, /model.toggleVisit/);
  assert.match(recipient, /visitButton/);
  const button = view.slice(view.indexOf('private var visitButton:'), view.indexOf('private var visitTitle:'));
  assert.match(button, /model.toggleVisit\(\)/);
  assert.match(button, /FishVisitDoorplateButtonStyle/);
  assert.match(button, /frame\(width: 56, height: 22\)/);
  for (const label of ['Cancel', 'Home', 'Visit']) assert.ok(button.includes(`"${label}"`));
  assert.match(button, /disabled\(model.isSending \|\| model.selectedContact == nil\)/);
  assert.match(button, /accessibilityLabel\(visitTitle\)/);
  assert.match(view, /editor.frame\(height: 58\)\s+interactionPanel\s+footer/);
  assert.match(view, /ForEach\(FishRemoteInteraction.allCases\)/);
  assert.match(controller, /combineLatest\(viewModel.\$interactionsExpanded\)/);
  assert.match(view, /if model.interactionsExpanded/);
});
