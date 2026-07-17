const test = require('node:test');
const assert = require('node:assert/strict');
const { PhraseEngine, matchesConditions, renderTemplate } = require('../src/core/phrase-engine');

test('conditions and placeholders require the matching context', () => {
  assert.equal(matchesConditions({ batteryEquals: 3 }, { battery: 3 }), true);
  assert.equal(matchesConditions({ batteryEquals: 3 }, { battery: 2 }), false);
  assert.equal(matchesConditions({ requires: ['title'] }, {}), false);
  assert.equal(renderTemplate('還有 {remaining} 個。', { remaining: 2 }), '還有 2 個。');
  assert.equal(renderTemplate('「{title}」要開始了。', {}), null);
});

test('selection respects conditions, cooldown and recent-history avoidance', () => {
  let now = 1000;
  const phrases = [
    { id: 'line-a', event: 'test.event', text: 'A', weight: 1, cooldownMs: 5000 },
    { id: 'line-b', event: 'test.event', text: 'B {count}', weight: 1, placeholders: ['count'] },
    { id: 'line-c', event: 'test.event', text: 'C', weight: 1, conditions: { activeCountMin: 2 } },
  ];
  const engine = new PhraseEngine(phrases, { random: () => 0, now: () => now, historyLimit: 2 });

  assert.equal(engine.select('test.event', { count: 1, activeCount: 1 }).id, 'line-a');
  assert.equal(engine.select('test.event', { count: 1, activeCount: 1 }).id, 'line-b');
  assert.equal(engine.select('test.event', { count: 1, activeCount: 2 }).id, 'line-c');
  now += 5000;
  assert.equal(engine.select('test.event', { count: 1, activeCount: 1 }).id, 'line-a');
});
