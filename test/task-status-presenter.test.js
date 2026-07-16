const test = require('node:test');
const assert = require('node:assert/strict');
const { getCurrentTaskStatus, getTerminalTaskStatus } = require('../src/core/task-status-presenter');

const tasks = [
  { provider: 'codex', state: 'running', title: '较早的任务', updatedAt: 1000 },
  { provider: 'claude-code', state: 'waiting', title: '等待确认的任务', updatedAt: 2000 },
];

test('shows the most recently updated task title and counts other active tasks', () => {
  assert.deepEqual(getCurrentTaskStatus(tasks, true), {
    state: 'waiting',
    title: '等待确认的任务',
    provider: 'claude-code',
    additionalCount: 1,
  });
});

test('uses a provider-only label when task title display is disabled', () => {
  assert.equal(getCurrentTaskStatus(tasks, false).title, 'Claude Code 任务');
});

test('completion retains the finished title before falling back to the remaining task', () => {
  const status = getTerminalTaskStatus(tasks[1], 'completed', [tasks[0]], true);
  assert.equal(status.state, 'completed');
  assert.equal(status.title, '等待确认的任务');
  assert.equal(status.additionalCount, 1);
  assert.deepEqual(status.next, {
    state: 'running',
    title: '较早的任务',
    provider: 'codex',
    additionalCount: 0,
  });
});

test('a hook stop remains a neutral ended state', () => {
  const status = getTerminalTaskStatus(tasks[1], 'ended', [tasks[0]], true);
  assert.equal(status.state, 'ended');
  assert.equal(status.title, '等待确认的任务');
});
