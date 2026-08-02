const test = require('node:test');
const assert = require('node:assert/strict');
const { MemoryGuard } = require('../src/core/memory-guard');

const SECOND = 1000;
const config = { enabled: true, limitMb: 1000 };

test('memory guard ignores startup, spikes and disabled protection', () => {
  const guard = new MemoryGuard({ startedAt: 0, graceMs: 5 * SECOND, sustainedMs: 3 * SECOND });
  assert.equal(guard.evaluate({ appMemoryMb: 1200 }, config, {}, 1000).reason, 'grace');
  assert.equal(guard.evaluate({ appMemoryMb: 1200 }, config, {}, 6000).reason, 'observing');
  assert.equal(guard.evaluate({ appMemoryMb: 900 }, config, {}, 7000).reason, 'below-limit');
  assert.equal(guard.evaluate({ appMemoryMb: 2000 }, { enabled: false, limitMb: 1000 }, {}, 9000).reason, 'disabled');
});

test('sustained pressure quits only when ordinary blockers are gone', () => {
  const guard = new MemoryGuard({ startedAt: 0, graceMs: 0, sustainedMs: 3 * SECOND });
  guard.evaluate({ appMemoryMb: 1100 }, config, {}, 1000);
  assert.equal(guard.evaluate({ appMemoryMb: 1100 }, config, { settingsOpen: true }, 4000).action, 'deferred');
  assert.equal(guard.evaluate({ appMemoryMb: 1100 }, config, {}, 5000).action, 'quit');
});

test('emergency pressure can bypass ordinary windows but never an update install', () => {
  const guard = new MemoryGuard({
    startedAt: 0,
    graceMs: 0,
    sustainedMs: 999 * SECOND,
    emergencySustainedMs: SECOND,
    emergencyMultiplier: 1.5,
  });
  guard.evaluate({ appMemoryMb: 1600 }, config, {}, 1000);
  assert.equal(guard.evaluate({ appMemoryMb: 1600 }, config, { settingsOpen: true }, 2000).action, 'quit');

  const updating = new MemoryGuard({
    startedAt: 0,
    graceMs: 0,
    sustainedMs: 999 * SECOND,
    emergencySustainedMs: SECOND,
    emergencyMultiplier: 1.5,
  });
  updating.evaluate({ appMemoryMb: 1600 }, config, {}, 1000);
  assert.equal(updating.evaluate({ appMemoryMb: 1600 }, config, { updateInstalling: true }, 2000).action, 'deferred');
});
