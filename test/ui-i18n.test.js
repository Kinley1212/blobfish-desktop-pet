const test = require('node:test');
const assert = require('node:assert/strict');

const {
  normalizeLocale,
  t,
  localizeCharacterCopy,
} = require('../src/core/ui-i18n');

test('interface locale supports Chinese and English with a safe Chinese fallback', () => {
  assert.equal(normalizeLocale('zh-CN'), 'zh-CN');
  assert.equal(normalizeLocale('en'), 'en');
  assert.equal(normalizeLocale('fr'), 'zh-CN');
  assert.equal(t('en', '任务状态'), 'Task status');
  assert.equal(t('zh-CN', '任务状态'), '任务状态');
});

test('character-specific English settings copy keeps each character voice', () => {
  const original = { pageTitle: '原始标题', savedStatus: '已保存。' };
  const fish = localizeCharacterCopy('blobfish', original, 'en');
  const grass = localizeCharacterCopy('grass-buddy', original, 'en');
  assert.equal(fish.pageTitle, 'Blobfish');
  assert.equal(grass.pageTitle, 'Grass Buddy');
  assert.notEqual(fish.savedStatus, grass.savedStatus);
  assert.equal(localizeCharacterCopy('blobfish', original, 'zh-CN'), original);
});
