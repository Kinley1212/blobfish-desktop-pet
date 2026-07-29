const test = require('node:test');
const assert = require('node:assert/strict');
const {
  shouldPauseIdleSpeech,
  shouldPauseMovement,
} = require('../src/core/activity-gates');

const active = {
  directlyPaused: false,
  contextMenuPaused: false,
  systemPaused: false,
  agentMovementPaused: false,
  hoverPaused: false,
  allTasksWaiting: false,
};

test('disabling no-task roaming pauses movement but not idle speech', () => {
  const noTaskRoamingDisabled = { ...active, agentMovementPaused: true };
  assert.equal(shouldPauseMovement(noTaskRoamingDisabled), true);
  assert.equal(shouldPauseIdleSpeech(noTaskRoamingDisabled), false);
});

test('interaction and system pauses still suppress both movement and idle speech', () => {
  for (const key of ['directlyPaused', 'contextMenuPaused', 'systemPaused', 'hoverPaused']) {
    const state = { ...active, [key]: true };
    assert.equal(shouldPauseMovement(state), true, `${key} should pause movement`);
    assert.equal(shouldPauseIdleSpeech(state), true, `${key} should pause idle speech`);
  }
});

test('a task waiting for attention keeps idle chatter out of the way', () => {
  const waiting = { ...active, agentMovementPaused: true, allTasksWaiting: true };
  assert.equal(shouldPauseMovement(waiting), true);
  assert.equal(shouldPauseIdleSpeech(waiting), true);
});
