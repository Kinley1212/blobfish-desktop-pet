const test = require('node:test');
const assert = require('node:assert/strict');
const {
  shouldPauseAgentMovement,
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

test('task and idle roaming switches form four independent movement modes', () => {
  const running = { activeCount: 1, waitingCount: 0 };
  const idle = { activeCount: 0, waitingCount: 0 };

  assert.equal(shouldPauseAgentMovement(running, { roamWhenTasks: true, roamWhenNoTasks: true }), false);
  assert.equal(shouldPauseAgentMovement(idle, { roamWhenTasks: true, roamWhenNoTasks: true }), false);

  assert.equal(shouldPauseAgentMovement(running, { roamWhenTasks: true, roamWhenNoTasks: false }), false);
  assert.equal(shouldPauseAgentMovement(idle, { roamWhenTasks: true, roamWhenNoTasks: false }), true);

  assert.equal(shouldPauseAgentMovement(running, { roamWhenTasks: false, roamWhenNoTasks: true }), true);
  assert.equal(shouldPauseAgentMovement(idle, { roamWhenTasks: false, roamWhenNoTasks: true }), false);

  assert.equal(shouldPauseAgentMovement(running, { roamWhenTasks: false, roamWhenNoTasks: false }), true);
  assert.equal(shouldPauseAgentMovement(idle, { roamWhenTasks: false, roamWhenNoTasks: false }), true);
});

test('waiting for attention pauses movement regardless of task roaming preference', () => {
  const waiting = { activeCount: 2, waitingCount: 2 };
  assert.equal(shouldPauseAgentMovement(waiting, { roamWhenTasks: true, roamWhenNoTasks: true }), true);
});
