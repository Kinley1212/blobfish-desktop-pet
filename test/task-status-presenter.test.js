const test = require('node:test');
const assert = require('node:assert/strict');
const { getCurrentTaskStatus, getTerminalTaskStatus } = require('../src/core/task-status-presenter');

const tasks = [
  { key: 'codex:one:turn', provider: 'codex', state: 'running', title: '较早的任务', updatedAt: 1000 },
  { key: 'claude-code:two:turn', provider: 'claude-code', state: 'waiting', title: '等待确认的任务', updatedAt: 2000 },
];

test('shows the most recently updated task title and counts other active tasks', () => {
  const status = getCurrentTaskStatus(tasks, true);
  assert.equal(status.taskKey, 'claude-code:two:turn');
  assert.equal(status.state, 'waiting');
  assert.equal(status.title, '等待确认的任务');
  assert.equal(status.additionalCount, 1);
  assert.deepEqual(status.items.map((item) => item.taskKey), [
    'claude-code:two:turn',
    'codex:one:turn',
  ]);
  assert.deepEqual(status.items.map((item) => item.state), ['waiting', 'running']);
});

test('uses a provider-only label when task title display is disabled', () => {
  assert.equal(getCurrentTaskStatus(tasks, false).title, 'Claude Code 任务');
});

test('completion retains the finished title before falling back to the remaining task', () => {
  const status = getTerminalTaskStatus(tasks[1], 'completed', [tasks[0]], true);
  assert.equal(status.state, 'completed');
  assert.equal(status.title, '等待确认的任务');
  assert.equal(status.additionalCount, 1);
  assert.deepEqual(status.items.map((item) => item.taskKey), [
    'claude-code:two:turn',
    'codex:one:turn',
  ]);
  assert.equal(status.next.taskKey, 'codex:one:turn');
  assert.equal(status.next.state, 'running');
  assert.equal(status.next.title, '较早的任务');
  assert.equal(status.next.provider, 'codex');
  assert.equal(status.next.additionalCount, 0);
});

test('a hook stop remains a neutral ended state', () => {
  const status = getTerminalTaskStatus(tasks[1], 'ended', [tasks[0]], true);
  assert.equal(status.state, 'ended');
  assert.equal(status.title, '等待确认的任务');
});
