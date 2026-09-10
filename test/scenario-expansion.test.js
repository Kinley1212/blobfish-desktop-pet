const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { loadLanguagePack } = require('../src/core/language-pack-loader');
const { PhraseEngine } = require('../src/core/phrase-engine');
const root = path.join(__dirname, '../src/packs/languages');
const read = (id) => JSON.parse(fs.readFileSync(path.join(root, id, 'additions/scenario-expansion.json'), 'utf8')).phrases;

test('each character gets 100 concise new lines across live scene events without raising frequency', () => {
  for (const id of fs.readdirSync(root)) {
    const phrases = read(id);
    assert.equal(phrases.length, 100, id);
    assert.ok(new Set(phrases.map((p) => p.event)).size >= 32, id);
    assert.equal(new Set(phrases.map((p) => p.text)).size, phrases.length, `${id}: repeated new text`);
    const all = loadLanguagePack(root, id);
    for (const phrase of phrases) {
      assert.equal(phrase.weight, 2);
      assert.ok(phrase.text.length <= (id.endsWith('-en') ? (id.startsWith('grass') ? 70 : 80) : 40), phrase.id);
      assert.doesNotMatch(phrase.text, /\{[^}]+\}/);
      assert.ok(all.phrases.some((p) => p.id === phrase.id), `${id}: manifest registration`);
      if (phrase.event === 'system.battery') assert.ok([20, 10, 5].includes(phrase.conditions.batteryEquals));
      if (['idle.chatter', 'messenger.visitIdle', 'system.unlocked'].includes(phrase.event)) assert.ok(phrase.cooldownMs >= 1800000);
    }
  }
});

test('translated scene pairs share exact triggering rules and cooldowns', () => {
  for (const [chinese, english] of [['blobfish-zh-TW', 'blobfish-en'], ['grass-buddy-zh-CN', 'grass-buddy-en']]) {
    const metadata = (p) => ({ event: p.event, weight: p.weight, conditions: p.conditions, cooldownMs: p.cooldownMs });
    assert.deepEqual(read(chinese).map(metadata), read(english).map(metadata));
  }
});

test('new conditional scenes select only with the supplied runtime context', () => {
  for (const id of fs.readdirSync(root)) {
    for (const phrase of read(id)) {
      const c = phrase.conditions || {};
      const context = {};
      if (c.hourMin !== undefined) context.hour = c.hourMin;
      if (c.hourMax !== undefined && context.hour === undefined) context.hour = c.hourMax;
      if (c.weekdays) context.weekday = c.weekdays[0];
      if (c.lockedMinSeconds !== undefined) context.lockedSeconds = c.lockedMinSeconds;
      if (c.batteryEquals !== undefined) context.battery = c.batteryEquals;
      if (c.activeCountMin !== undefined) context.activeCount = c.activeCountMin;
      if (c.remainingMin !== undefined) context.remaining = c.remainingMin;
      if (c.remainingEquals !== undefined) context.remaining = c.remainingEquals;
      const make = () => new PhraseEngine([phrase], { now: () => 1000, random: () => 0 });
      assert.equal(make().select(phrase.event, context)?.id, phrase.id);
      if (Object.keys(c).length > 0) assert.equal(make().select(phrase.event, {}), null, phrase.id);
    }
  }
});
