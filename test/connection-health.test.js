const test = require('node:test');
const assert = require('node:assert/strict');
const { ConnectionHealthTracker } = require('../src/core/connection-health');

test('connection health requires a real event after a test starts', () => {
  let now = 1000;
  const tracker = new ConnectionHealthTracker({ now: () => now, testTimeoutMs: 60000 });

  assert.equal(tracker.decorate('codex', { state: 'connected' }).health, 'unverified');
  const waiting = tracker.startTest('codex');
  assert.equal(waiting.health, 'awaiting-event');
  assert.equal(waiting.testExpiresAt, 61000);

  now = 62000;
  assert.equal(tracker.snapshot('codex').health, 'test-timeout');

  now = 63000;
  const active = tracker.noteEvent('codex');
  assert.equal(active.health, 'active');
  assert.equal(active.lastEventAt, 63000);
  assert.equal(active.testStartedAt, null);
});

test('installation failures stay unavailable without erasing last event time', () => {
  let now = 5000;
  const tracker = new ConnectionHealthTracker({ now: () => now });
  tracker.noteEvent('claude');

  const disabled = tracker.decorate('claude', { state: 'disabled', installed: true });
  assert.equal(disabled.health, 'unavailable');
  assert.equal(disabled.lastEventAt, 5000);

  now = 6000;
  assert.equal(tracker.clear('claude').health, 'unverified');
  assert.equal(tracker.snapshot('claude').lastEventAt, null);
});

test('connection health rejects unknown providers', () => {
  const tracker = new ConnectionHealthTracker();
  assert.throws(() => tracker.startTest('unknown'), /不支持/);
});
