const test = require('node:test');
const assert = require('node:assert/strict');
const { playTaskSoundFile } = require('../src/core/sound-player');

test('plays macOS task sounds through afplay', () => {
  const calls = [];
  const result = playTaskSoundFile('/System/Library/Sounds/Glass.aiff', {
    platform: 'darwin',
    execFile: (command, args, callback) => {
      calls.push({ command, args });
      callback(null);
    },
  });

  assert.equal(result, true);
  assert.deepEqual(calls, [{
    command: '/usr/bin/afplay',
    args: ['/System/Library/Sounds/Glass.aiff'],
  }]);
});

test('falls back to a system beep when afplay fails', () => {
  const errors = [];
  let beeped = false;
  const result = playTaskSoundFile('/System/Library/Sounds/Glass.aiff', {
    platform: 'darwin',
    execFile: (_command, _args, callback) => callback(new Error('AudioQueueStart failed')),
    beep: () => { beeped = true; },
    onError: (error) => errors.push(error.message),
  });

  assert.equal(result, true);
  assert.equal(beeped, true);
  assert.deepEqual(errors, ['AudioQueueStart failed']);
});

test('uses a system beep on non-macOS platforms', () => {
  let beeped = false;
  const result = playTaskSoundFile('/unused/sound.aiff', {
    platform: 'win32',
    beep: () => { beeped = true; },
  });

  assert.equal(result, true);
  assert.equal(beeped, true);
});

test('rejects an empty sound path without beeping', () => {
  let beeped = false;
  const result = playTaskSoundFile(null, {
    platform: 'darwin',
    beep: () => { beeped = true; },
  });

  assert.equal(result, false);
  assert.equal(beeped, false);
});
