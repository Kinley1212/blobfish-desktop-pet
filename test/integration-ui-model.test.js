const test = require('node:test');
const assert = require('node:assert/strict');

const { describeAgentIntegration } = require('../src/core/integration-ui-model');

const STATES = [
  'checking',
  'legacy',
  'connected',
  'disabled',
  'not-installed',
  'cli-missing',
  'opened',
  'opened-disconnect',
  'terminal-opened',
  'conflict',
  'error',
  'unknown',
];

for (const provider of ['codex', 'claude']) {
  test(`${provider} presents one explicit next step for every plugin state`, () => {
    for (const state of STATES) {
      const result = describeAgentIntegration(provider, { state, operation: 'install' });
      assert.ok(result.verdict, `${state} requires a verdict`);
      assert.ok(result.summary, `${state} requires a summary`);
      assert.ok(result.instruction, `${state} requires an instruction`);
      assert.ok(result.primary.label, `${state} requires one primary label`);
      assert.ok(['none', 'manage', 'verify', 'refresh', 'details'].includes(result.primary.action));
      assert.equal(typeof result.primary.disabled, 'boolean');
    }
  });
}

test('legacy plugins get a single automatic upgrade action', () => {
  const result = describeAgentIntegration('codex', { state: 'legacy', version: '0.1.0' });
  assert.equal(result.verdict, '需要升级');
  assert.equal(result.primary.action, 'manage');
  assert.equal(result.primary.label, '升级并连接');
  assert.match(result.instruction, /自动升级并连接/);
});

test('a managed plugin asks for verification instead of repair', () => {
  const result = describeAgentIntegration('claude', { state: 'connected', version: '0.2.0' });
  assert.equal(result.verdict, '等待验证');
  assert.deepEqual(result.primary, { action: 'verify', label: '开始验证', disabled: false });
});

test('live and waiting health override lower-level plugin states', () => {
  const live = describeAgentIntegration('codex', {
    state: 'error',
    health: 'active',
  }, { lastEventLabel: '今天 09:30' });
  assert.equal(live.verdict, '已连接');
  assert.equal(live.primary.disabled, true);
  assert.match(live.summary, /今天 09:30/);

  const waiting = describeAgentIntegration('claude', {
    state: 'connected',
    health: 'awaiting-event',
  });
  assert.equal(waiting.verdict, '等待验证');
  assert.equal(waiting.primary.action, 'none');
  assert.match(waiting.instruction, /重新打开 Claude Code 会话/);
});

test('timed-out verification tells the user to retry before creating another event', () => {
  const result = describeAgentIntegration('codex', {
    state: 'connected',
    health: 'test-timeout',
  });
  assert.equal(result.primary.label, '重新验证');
  assert.match(result.instruction, /^点击“重新验证”，然后/);
});
