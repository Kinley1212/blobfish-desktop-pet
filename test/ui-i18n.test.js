const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  normalizeLocale,
  t,
  localizeCharacterCopy,
  localizeCharacterName,
  localizeAccessoryName,
  localizeSoundName,
} = require('../src/core/ui-i18n');
const diyModel = require('../src/core/diy-model');
const accessoryModel = require('../src/core/accessory-model');
const { loadAccessoryCatalog } = require('../src/core/accessory-loader');
const { loadCharacterPack } = require('../src/core/pack-loader');

const chinesePattern = /[\u3400-\u9fff]/u;

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

test('every dynamic DIY label and shape preset has an English rendering', () => {
  const labels = [
    ...diyModel.DIY_CONTROLS.flatMap((group) => [group.label, ...group.fields.map((field) => field.label)]),
    ...Object.values(diyModel.SHAPE_GROUPS).map((group) => group.label),
    ...accessoryModel.ACCESSORY_SLOTS.flatMap((slot) => [slot.label, slot.empty]).filter(Boolean),
    ...accessoryModel.ACCESSORY_FIELDS.map((field) => field.label),
  ];
  for (const label of labels) assert.doesNotMatch(t('en', label), chinesePattern, label);

  const charactersRoot = path.join(__dirname, '..', 'src', 'packs', 'characters');
  for (const entry of fs.readdirSync(charactersRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const pack = loadCharacterPack(charactersRoot, entry.name);
    assert.doesNotMatch(
      localizeCharacterName(pack.manifest.id, pack.manifest.displayName, 'en'),
      chinesePattern,
      pack.manifest.id,
    );
    for (const options of Object.values(pack.manifest.diy?.shapes || {})) {
      for (const option of options) assert.doesNotMatch(t('en', option.label), chinesePattern, option.label);
    }
  }
});

test('every accessory and sound option has an English display name', () => {
  const accessoriesRoot = path.join(__dirname, '..', 'src', 'packs', 'accessories');
  for (const item of loadAccessoryCatalog(accessoriesRoot)) {
    assert.doesNotMatch(localizeAccessoryName(item.id, item.displayName, 'en'), chinesePattern, item.id);
  }
  assert.equal(localizeSoundName('Glass', '玻璃叮（清脆）', 'en'), 'Glass (bright chime)');
});
