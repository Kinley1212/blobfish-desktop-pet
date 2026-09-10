const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { t } = require('../src/core/ui-i18n');
const native = (file) => fs.readFileSync(path.join(__dirname, '../native-appkit/Sources/BlobfishNative', file), 'utf8');

test('movement and panel controls have complete English labels', () => {
  for (const label of ['碰到边界后转身', '甩动或游动撞到屏幕边缘时，让角色面向反弹方向。',
    '面板位置', '角色左侧', '角色右侧', '上下位置', '离角色距离']) {
    assert.doesNotMatch(t('en', label), /[\u3400-\u9fff]/u, label);
    assert.equal(t('zh-CN', label), label);
  }
});

test('pet chat uses the active pack without a cross-character fallback', () => {
  const source = native('AppDelegate.swift');
  const open = source.slice(source.indexOf('@MainActor @objc private func openDialogue()'), source.indexOf('@objc private func openSettings()'));
  assert.match(open, /runtime\.language\?\.id/);
  assert.doesNotMatch(open, /dialogue\(id: "blobfish-zh-TW"\)/);
  const settings = source.slice(source.indexOf('@objc private func openSettings()'));
  assert.match(settings, /dialogueController\?\.synchronize\(pack: pack\)/);
  const invitation = source.slice(source.indexOf('private func scheduleChatInvite()'), source.indexOf('private func handleClockEvent'));
  assert.match(invitation, /runtime\.speechIsEnglish/);
  assert.doesNotMatch(invitation, /config\.ui\.locale/);
});

test('native minigames select the speech locale and describe the actual dice range', () => {
  const source = native('DialogueWindowController.swift');
  assert.match(source, /runtime\.speechText\(chinese, english\)/);
  assert.match(source, /Big \(8–12\)/);
  assert.match(source, /Small \(2–6\)/);
  assert.match(source, /if changed \{ startFresh\(\) \}/);
});

test('changing speech identity clears only automatic speech, not friend messages', () => {
  const source = native('PetPanelController.swift');
  const apply = source.slice(source.indexOf('func apply(runtime:'), source.indexOf('func centerOnPrimaryScreen()'));
  assert.match(apply, /speechPackID != runtime\.language\?\.id/);
  assert.match(apply, /petView\.character\?\.id != runtime\.character\?\.id/);
  assert.match(apply, /if speechChanged \{ speechQueue\.clear\(\) \}/);
  assert.doesNotMatch(apply, /friend.*clear|clearSpeakingPresentation/);
});
