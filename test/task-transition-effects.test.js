const test = require('node:test');
const assert = require('node:assert/strict');
const { getTaskSoundCue } = require('../src/core/task-transition-effects');

test('plays the configured finish cue for completed and neutral ended transitions', () => {
  for (const transition of ['completed', 'allCompleted', 'ended', 'allEnded']) {
    assert.equal(getTaskSoundCue(transition), 'taskComplete');
  }
});

test('keeps approval and failure sound semantics separate', () => {
  assert.equal(getTaskSoundCue('needsInput'), 'needsInput');
  assert.equal(getTaskSoundCue('failed'), null);
  assert.equal(getTaskSoundCue('started'), null);
  assert.equal(getTaskSoundCue('state'), null);
});
