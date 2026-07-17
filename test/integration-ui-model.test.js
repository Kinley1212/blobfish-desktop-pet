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
      assert.ok(['none', 'manage', 'update', 'verify', 'refresh', 'details', 'enable'].includes(result.primary.action));
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
  const result = describeAgentIntegration('codex', { state: 'connected', version: '0.2.0' });
  assert.equal(result.verdict, '等待授权');
  assert.deepEqual(result.primary, { action: 'verify', label: '我已授权，开始验证', disabled: false });
  const claude = describeAgentIntegration('claude', { state: 'connected', version: '0.2.0' });
  assert.equal(claude.verdict, '等待验证');
  assert.deepEqual(claude.primary, { action: 'verify', label: '开始验证', disabled: false });
});

test('an outdated live plugin asks for one-click update before claiming no action is needed', () => {
  const result = describeAgentIntegration('codex', {
    state: 'connected',
    health: 'active',
    version: '0.2.0',
    bundledVersion: '0.2.1',
    updateAvailable: true,
  });
  assert.equal(result.verdict, '需要更新');
  assert.deepEqual(result.primary, { action: 'update', label: '一键更新连接', disabled: false });
  assert.match(result.instruction, /开启任务标题后/);
});

test('verified and waiting health are shown for a usable plugin', () => {
  const live = describeAgentIntegration('codex', {
    state: 'connected',
    health: 'active',
  }, { lastEventLabel: '今天 09:30' });
  assert.equal(live.verdict, '已验证');
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

test('conflicts and errors cannot be hidden by a previously received event', () => {
  for (const state of ['conflict', 'error', 'disabled']) {
    const result = describeAgentIntegration('codex', { state, health: 'active' });
    assert.notEqual(result.verdict, '已验证');
    assert.equal(result.verdictState, 'disconnected');
  }
});

test('turning off reception is distinct from uninstalling the plugin', () => {
  const result = describeAgentIntegration('codex', {
    state: 'connected',
    health: 'active',
    receiveEnabled: false,
  });
  assert.equal(result.verdict, '已暂停');
  assert.deepEqual(result.primary, { action: 'enable', label: '恢复接收任务状态', disabled: false });
});

test('an in-progress operation stays locked even if polling sees an intermediate state', () => {
  const result = describeAgentIntegration('claude', {
    state: 'not-installed',
    operationBusy: true,
    operation: 'install',
  });
  assert.equal(result.verdict, '连接中');
  assert.equal(result.primary.disabled, true);
  assert.match(result.summary, /Terminal/);
});

test('timed-out verification tells the user to retry before creating another event', () => {
  const result = describeAgentIntegration('codex', {
    state: 'connected',
    health: 'test-timeout',
  });
  assert.equal(result.primary.label, '重新验证');
  assert.match(result.instruction, /\/hooks.*重新验证/);
});
