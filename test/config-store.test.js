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
    next.greetings.workday.start = '06:45';
    next.greetings.workday.end = '10:30';
    next.language.idleMinMinutes = 20;
    next.language.idleMaxMinutes = 45;
    next.pet.scale = 1.25;
    next.pet.characterPackId = 'grass-buddy';
    next.pet.roamWhenNoTasks = true;
    next.startup.launchAtLogin = true;
    store.save(next);

    const reloaded = new ConfigStore(directory);
    assert.equal(reloaded.load().schedule.lunchTime, '12:30');
    assert.deepEqual(reloaded.get().schedule.workdays, [1, 3, 5]);
    assert.deepEqual(reloaded.get().greetings.workday, { enabled: true, start: '06:45', end: '10:30' });
    assert.equal(reloaded.get().pet.scale, 1.25);
    assert.equal(reloaded.get().pet.characterPackId, 'grass-buddy');
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
  delete legacy.pet.characterPackId;
  delete legacy.pet.roamWhenNoTasks;
  legacy.pet.stopWhenAllTasksComplete = true;
  delete legacy.startup;
  delete legacy.greetings;
  assert.deepEqual(validateConfig(legacy).pet, {
    characterPackId: 'blobfish',
    speed: 1.5,
    scale: 1,
    roamWhenNoTasks: false,
    moveAxis: 'horizontal',
    customization: {},
    accessories: {},
  });
  assert.deepEqual(validateConfig(legacy).startup, { launchAtLogin: false });
  assert.deepEqual(validateConfig(legacy).greetings, DEFAULT_CONFIG.greetings);
});

test('task-complete sound setting round-trips and defends against bad input', () => {
  const { DEFAULT_TASK_COMPLETE_SOUND_ID } = require('../src/core/sound-catalog');

  // A valid custom choice survives validation unchanged.
  const custom = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  custom.sound = { taskComplete: { enabled: false, soundId: 'Submarine' } };
  assert.deepEqual(validateConfig(custom).sound.taskComplete, {
    enabled: false,
    soundId: 'Submarine',
  });

  // A config saved before the sound feature existed migrates to defaults
  // instead of throwing.
  const legacy = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  delete legacy.sound;
  assert.deepEqual(validateConfig(legacy).sound.taskComplete, {
    enabled: true,
    soundId: DEFAULT_TASK_COMPLETE_SOUND_ID,
  });

  // An unknown sound id (e.g. removed in a later version) falls back to the
  // default rather than bricking the whole config load.
  const unknown = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  unknown.sound = { taskComplete: { enabled: true, soundId: 'NotARealSound' } };
  assert.equal(validateConfig(unknown).sound.taskComplete.soundId, DEFAULT_TASK_COMPLETE_SOUND_ID);
});

test('invalid config is rejected without weakening validation', () => {
  const invalid = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  invalid.schedule.offWorkTime = '25:99';
  assert.throws(() => validateConfig(invalid), /HH:MM/);

  invalid.schedule.offWorkTime = '19:00';
  invalid.language.idleMinMinutes = 50;
  invalid.language.idleMaxMinutes = 10;
  assert.throws(() => validateConfig(invalid), /cannot exceed/);

  invalid.language.idleMinMinutes = 10;
  invalid.greetings.workday.start = '11:00';
  invalid.greetings.workday.end = '07:00';
  assert.throws(() => validateConfig(invalid), /must be earlier/);
});
