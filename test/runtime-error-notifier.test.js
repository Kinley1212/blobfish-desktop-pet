const test = require('node:test');
const assert = require('node:assert/strict');
const { RuntimeErrorNotifier } = require('../src/core/runtime-error-notifier');

test('runtime errors wait for the pet window and use a global cooldown', () => {
  let now = 1000;
  const spoken = [];
  const logged = [];
  const notifier = new RuntimeErrorNotifier(
    () => {
      spoken.push(now);
      return true;
    },
    {
      cooldownMs: 300000,
      now: () => now,
      log: (message) => logged.push(message),
    },
  );

  assert.equal(notifier.report('Agent bridge', new Error('socket failed')), false);
  assert.deepEqual(spoken, []);
  assert.equal(notifier.setReady(), true);
  assert.deepEqual(spoken, [1000]);

  now += 1000;
  assert.equal(notifier.report('Calendar', 'permission failed'), false);
  assert.deepEqual(spoken, [1000]);

  now += 300000;
  assert.equal(notifier.report('Codex connection', new Error('not installed')), true);
  assert.deepEqual(spoken, [1000, 302000]);
  assert.deepEqual(logged, [
    'Agent bridge: socket failed',
    'Calendar: permission failed',
    'Codex connection: not installed',
  ]);
});

test('a suppressed notification does not start the cooldown', () => {
  let attempts = 0;
  const notifier = new RuntimeErrorNotifier(() => {
    attempts += 1;
    return attempts > 1;
  }, { log: () => {} });

  notifier.setReady();
  assert.equal(notifier.report('First', 'hidden'), false);
  assert.equal(notifier.report('Second', 'visible'), true);
  assert.equal(attempts, 2);
});
