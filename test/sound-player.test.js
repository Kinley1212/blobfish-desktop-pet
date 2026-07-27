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
  assert.deepEqual(calls, [
    { command: '/usr/bin/afplay', args: ['/System/Library/Sounds/Glass.aiff'] },
  ]);
});

test('falls back to a system beep when afplay fails', () => {
  let beepCount = 0;
  const errors = [];
  const playbackError = new Error('AudioQueueStart failed');
  const result = playTaskSoundFile('/System/Library/Sounds/Glass.aiff', {
    platform: 'darwin',
    execFile: (command, args, callback) => callback(playbackError),
    beep: () => {
      beepCount += 1;
    },
    onError: (error) => errors.push(error),
  });

  assert.equal(result, true);
  assert.equal(beepCount, 1);
  assert.deepEqual(errors, [playbackError]);
});

test('uses a system beep on non-macOS platforms', () => {
  let beepCount = 0;
  const result = playTaskSoundFile('/unused/sound.aiff', {
    platform: 'win32',
    beep: () => {
      beepCount += 1;
    },
  });

  assert.equal(result, true);
  assert.equal(beepCount, 1);
});

test('does not play without a sound path', () => {
  const result = playTaskSoundFile(null, {
    platform: 'darwin',
    execFile: () => {
      throw new Error('should not play');
    },
  });

  assert.equal(result, false);
});
