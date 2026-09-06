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
  assert.match(view, /TextEditor\(text: \$model.draft\)/);
  assert.match(view, /keyboardShortcut\(\.return, modifiers: \[\.command\]\)/);
  assert.match(view, /editor.hasMarkedText\(\) \{ return \}[\s\S]*?model.sendMessage\(\)/);
  assert.doesNotMatch(view, /onSubmit|makeFirstResponder\(nil\)/);
  assert.match(view, /disabled\(model.sendDisabled\)/);
});

test('stationery pairs paper and ink in both appearances without outlined art', () => {
  for (const token of ['backdrop', 'paper', 'ink', 'muted']) {
    assert.match(view, new RegExp('var ' + token + ': Color \\{ dark \\?'));
  }
  assert.match(view, /colorScheme == \.dark/);
  assert.doesNotMatch(view, /\.stroke\(|\.strokeBorder\(/);
});
