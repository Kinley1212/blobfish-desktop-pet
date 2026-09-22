const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { loadLanguagePack } = require('../src/core/language-pack-loader');
const { PhraseEngine } = require('../src/core/phrase-engine');

test('every speech pack renders coral hiding durations and a return greeting', () => {
  const root = path.join(__dirname, '../src/packs/languages');
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const pack = loadLanguagePack(root, entry.name);
    for (const minutes of [1, 5, 15, 30]) {
      const engine = new PhraseEngine(pack.phrases, { random: () => 0 });
      const hiding = engine.select('interaction.hide', { minutes });
      assert.ok(hiding, entry.name);
      assert.ok(hiding.text.includes(String(minutes)), entry.name);
      assert.doesNotMatch(hiding.text, /\{minutes\}/);
      assert.ok(engine.select('interaction.return', {}).text.trim(), entry.name);
    }
  }
});
