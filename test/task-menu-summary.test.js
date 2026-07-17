const test = require('node:test');
const assert = require('node:assert/strict');
const { formatProviderTaskSummary } = require('../src/core/task-menu-summary');

test('formats idle, disabled and single-state provider summaries', () => {
  assert.equal(formatProviderTaskSummary([], 'codex', 'Codex'), 'Codex：空闲');
  assert.equal(formatProviderTaskSummary([], 'codex', 'Codex', false), 'Codex：未启用');
  assert.equal(formatProviderTaskSummary([
    { provider: 'codex', state: 'running' },
    { provider: 'codex', state: 'running' },
  ], 'codex', 'Codex'), 'Codex：运行 2');
  assert.equal(formatProviderTaskSummary([
    { provider: 'claude-code', state: 'waiting' },
  ], 'claude-code', 'Claude'), 'Claude：等待确认 1');
});

test('formats mixed running and waiting tasks without counting another provider', () => {
  const tasks = [
    { provider: 'codex', state: 'running' },
    { provider: 'codex', state: 'waiting' },
    { provider: 'claude-code', state: 'waiting' },
  ];
  assert.equal(formatProviderTaskSummary(tasks, 'codex', 'Codex'), 'Codex：运行 1 · 等待 1');
  assert.equal(formatProviderTaskSummary(tasks, 'claude-code', 'Claude'), 'Claude：等待确认 1');
});
