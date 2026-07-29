const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { ClockStore } = require('../src/core/clock-store');
const { DEFAULT_CLOCK_STATE } = require('../src/core/clock-engine');

test('clock store round-trips validated state with private permissions', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-clock-'));
  try {
    const store = new ClockStore(directory);
    store.load();
    const saved = store.save({
      ...JSON.parse(JSON.stringify(DEFAULT_CLOCK_STATE)),
      lastReconciledAtMs: 123,
    });
    assert.equal(saved.lastReconciledAtMs, 123);
    assert.equal(new ClockStore(directory).load().lastReconciledAtMs, 123);
    assert.equal(fs.statSync(path.join(directory, 'clock-state.json')).mode & 0o777, 0o600);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('clock store reports corrupt data and returns an empty state', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-clock-bad-'));
  try {
    fs.writeFileSync(path.join(directory, 'clock-state.json'), '{bad', 'utf8');
    const store = new ClockStore(directory);
    const loaded = store.load();
    assert.equal(loaded.alarms.length, 0);
    assert.match(store.loadWarning, /闹钟与计时记录无效/);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
