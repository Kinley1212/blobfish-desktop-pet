const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { ConfigStore, DEFAULT_CONFIG, validateConfig } = require('../src/core/config-store');

test('config store writes validated settings atomically and reloads them', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-config-'));
  try {
    const store = new ConfigStore(directory);
    const next = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
    next.schedule.lunchTime = '12:30';
    next.schedule.workdays = [5, 1, 1, 3];
    next.language.idleMinMinutes = 20;
    next.language.idleMaxMinutes = 45;
    next.pet.scale = 1.25;
    next.pet.roamWhenNoTasks = true;
    next.startup.launchAtLogin = true;
    store.save(next);

    const reloaded = new ConfigStore(directory);
    assert.equal(reloaded.load().schedule.lunchTime, '12:30');
    assert.deepEqual(reloaded.get().schedule.workdays, [1, 3, 5]);
    assert.equal(reloaded.get().pet.scale, 1.25);
    assert.equal(reloaded.get().pet.roamWhenNoTasks, true);
    assert.equal(reloaded.get().startup.launchAtLogin, true);
    assert.equal(fs.statSync(reloaded.filePath).mode & 0o777, 0o600);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('legacy stop-after-task setting migrates without losing user intent', () => {
  const legacy = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  delete legacy.pet.scale;
  delete legacy.pet.roamWhenNoTasks;
  legacy.pet.stopWhenAllTasksComplete = true;
  delete legacy.startup;
  assert.deepEqual(validateConfig(legacy).pet, {
    speed: 1.5,
    scale: 1,
    roamWhenNoTasks: false,
  });
  assert.deepEqual(validateConfig(legacy).startup, { launchAtLogin: false });
});

test('invalid config is rejected without weakening validation', () => {
  const invalid = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  invalid.schedule.offWorkTime = '25:99';
  assert.throws(() => validateConfig(invalid), /HH:MM/);

  invalid.schedule.offWorkTime = '19:00';
  invalid.language.idleMinMinutes = 50;
  invalid.language.idleMaxMinutes = 10;
  assert.throws(() => validateConfig(invalid), /cannot exceed/);
});
