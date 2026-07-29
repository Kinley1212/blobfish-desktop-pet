const test = require('node:test');
const assert = require('node:assert/strict');
const { ProcessedAgentEvents, TaskTracker } = require('../src/core/task-tracker');

function event(eventName, turnId, timestamp = 1000, sessionId = 'session') {
  return { version: 1, provider: 'codex', event: eventName, sessionId, turnId, timestamp };
}

test('tracks separate conversations, waiting state, single completion and all complete', () => {
  const transitions = [];
  const tracker = new TaskTracker((transition) => transitions.push(transition));
  tracker.handle(event('started', 'one', 1000, 'session-one'));
  tracker.handle(event('started', 'two', 1000, 'session-two'));
  tracker.handle(event('needs_input', 'one', 2000, 'session-one'));
  tracker.handle(event('needs_input', 'one', 2100, 'session-one'));
  tracker.handle(event('completed', 'one', 3000, 'session-one'));
  tracker.handle(event('completed', 'two', 3000, 'session-two'));

  assert.deepEqual(
    transitions.filter((transition) => transition.type !== 'state').map((transition) => transition.type),
    ['started', 'started', 'needsInput', 'completed', 'allCompleted'],
  );
  assert.deepEqual(tracker.snapshot(), { activeCount: 0, waitingCount: 0, runningCount: 0 });
});

test('ignores tool and permission events that have no explicit prompt start', () => {
  const transitions = [];
  const tracker = new TaskTracker((transition) => transitions.push(transition));
  tracker.handle(event('running', 'ghost', 1000));
  tracker.handle(event('needs_input', 'ghost', 2000));

  assert.equal(tracker.snapshot().activeCount, 0);
  assert.deepEqual(transitions, []);
});

test('does not permanently deduplicate needs_input when it arrives before its task start', () => {
  const transitions = [];
  const tracker = new TaskTracker((transition) => transitions.push(transition.type));
  const processed = new ProcessedAgentEvents();
  const waiting = event('needs_input', 'out-of-order-turn', 2000);

  const socketResult = tracker.handleWithResult(waiting);
  if (socketResult.accepted) processed.remember(waiting);

  assert.equal(socketResult.accepted, false);
  assert.equal(processed.has(waiting), false);

  tracker.handle(event('started', 'out-of-order-turn', 1000));
  assert.deepEqual(tracker.snapshot(), { activeCount: 1, waitingCount: 1, runningCount: 0 });
  assert.deepEqual(transitions, ['started', 'needsInput']);

  tracker.handle(waiting);
  assert.equal(transitions.filter((type) => type === 'needsInput').length, 1);
});

test('pending lifecycle is matched by turn and a late old start cannot consume a newer turn', () => {
  const transitions = [];
  const tracker = new TaskTracker((transition) => transitions.push(transition.type));

  tracker.handle(event('needs_input', 'new-turn', 3000));
  tracker.handle(event('started', 'old-turn', 1000));
  assert.equal(tracker.getTasks()[0].state, 'running');
  tracker.handle(event('started', 'new-turn', 2000));

  assert.equal(tracker.getTasks()[0].turnId, 'new-turn');
  assert.equal(tracker.getTasks()[0].state, 'waiting');
  assert.deepEqual(transitions, ['started', 'started', 'needsInput']);

  const another = new TaskTracker((transition) => transitions.push(`another:${transition.type}`));
  another.handle(event('needs_input', 'old-turn', 2000));
  another.handle(event('started', 'new-turn', 3000));
  assert.equal(another.getTasks()[0].state, 'running');
  assert.equal(transitions.includes('another:needsInput'), false);
});

test('pending lifecycle has a short TTL and a hard size bound', () => {
  let now = 0;
  const transitions = [];
  const tracker = new TaskTracker(
    (transition) => transitions.push(transition.type),
    {
      maxPendingLifecycleEvents: 2,
      now: () => now,
      pendingLifecycleMaxAgeMs: 100,
    },
  );

  tracker.handle(event('needs_input', 'one', 1000, 'session-one'));
  tracker.handle(event('needs_input', 'two', 1000, 'session-two'));
  tracker.handle(event('needs_input', 'three', 1000, 'session-three'));
  tracker.handle(event('started', 'one', 1100, 'session-one'));
  tracker.handle(event('started', 'three', 1100, 'session-three'));

  assert.equal(tracker.getTasks().find((task) => task.sessionId === 'session-one').state, 'running');
  assert.equal(tracker.getTasks().find((task) => task.sessionId === 'session-three').state, 'waiting');
  assert.equal(transitions.filter((type) => type === 'needsInput').length, 1);

  tracker.handle(event('needs_input', 'four', 2000, 'session-four'));
  now = 101;
  tracker.pruneStale(10_000, 2_000);
  tracker.handle(event('started', 'four', 2100, 'session-four'));
  assert.equal(tracker.getTasks().find((task) => task.sessionId === 'session-four').state, 'running');
  assert.equal(transitions.filter((type) => type === 'needsInput').length, 1);
});

test('terminal events and provider removal clear pending lifecycle', () => {
  const transitions = [];
  const tracker = new TaskTracker((transition) => transitions.push(transition.type));

  tracker.handle(event('needs_input', 'terminal-turn', 1000, 'terminal-session'));
  tracker.handle(event('ended', 'terminal-turn', 2000, 'terminal-session'));
  tracker.handle(event('started', 'terminal-turn', 3000, 'terminal-session'));
  assert.equal(tracker.getTasks().find((task) => task.sessionId === 'terminal-session').state, 'running');

  const claudeWaiting = {
    ...event('needs_input', 'claude-turn', 1000, 'claude-session'),
    provider: 'claude-code',
  };
  const claudeStarted = {
    ...event('started', 'claude-turn', 2000, 'claude-session'),
    provider: 'claude-code',
  };
  tracker.handle(claudeWaiting);
  tracker.removeProvider('claude-code');
  tracker.handle(claudeStarted);

  assert.equal(tracker.getTasks().find((task) => task.sessionId === 'claude-session').state, 'running');
  assert.equal(transitions.includes('needsInput'), false);
});

test('uses one card per conversation and moves it to a newer turn', () => {
  const transitions = [];
  const tracker = new TaskTracker((transition) => transitions.push(transition.type));
  tracker.handle({ ...event('started', 'turn-one', 1000), title: '整理发布说明' });
  tracker.handle({ ...event('started', 'turn-two', 2000), title: '继续' });

  const tasks = tracker.getTasks();
  assert.equal(tasks.length, 1);
  assert.equal(tasks[0].turnId, 'turn-two');
  assert.equal(tasks[0].title, '整理发布说明');
  assert.equal(tasks[0].startedAt, 2000);
  assert.deepEqual(transitions, ['started', 'started']);
});

test('a meaningful title from a newer turn replaces the previous turn title', () => {
  const tracker = new TaskTracker();
  tracker.handle({ ...event('started', 'turn-one', 1000), title: '整理发布说明' });
  tracker.handle({ ...event('started', 'turn-two', 2000), title: '修复任务恢复' });

  assert.equal(tracker.getTasks()[0].title, '修复任务恢复');
});

test('a stale stop from the previous turn cannot close the current turn', () => {
  const tracker = new TaskTracker();
  tracker.handle(event('started', 'turn-one', 1000));
  tracker.handle(event('started', 'turn-two', 2000));
  tracker.handle(event('ended', 'turn-one', 3000));

  assert.equal(tracker.snapshot().activeCount, 1);
  assert.equal(tracker.getTasks()[0].turnId, 'turn-two');
});

test('a terminal event without a turn id closes the current conversation', () => {
  const tracker = new TaskTracker();
  tracker.handle(event('started', 'turn-one', 1000));
  tracker.handle({ ...event('ended', null, 2000), turnId: null });
  assert.equal(tracker.snapshot().activeCount, 0);
});

test('failed tasks end without claiming successful all-complete and stale tasks are pruned', () => {
  const transitions = [];
  const tracker = new TaskTracker((transition) => transitions.push(transition.type));
  tracker.handle(event('started', 'failed', 1000));
  tracker.handle(event('failed', 'failed', 2000));
  tracker.handle(event('started', 'stale', 3000));
  assert.equal(tracker.pruneStale(5000, 9001), 1);
  assert.deepEqual(transitions, ['started', 'failed', 'started', 'state']);
});

test('waiting tasks use a longer stale fallback than running tasks', () => {
  const tracker = new TaskTracker();
  tracker.handle(event('started', 'running', 1000, 'running-session'));
  tracker.handle(event('started', 'waiting', 1000, 'waiting-session'));
  tracker.handle(event('needs_input', 'waiting', 2000, 'waiting-session'));

  assert.equal(tracker.pruneStale(5000, 7001, 10000), 1);
  assert.equal(tracker.getTasks()[0].state, 'waiting');
});

test('hook stops end tasks without claiming successful completion', () => {
  const transitions = [];
  const tracker = new TaskTracker((transition) => transitions.push(transition.type));
  tracker.handle(event('started', 'one', 1000, 'session-one'));
  tracker.handle(event('started', 'two', 1000, 'session-two'));
  tracker.handle(event('ended', 'one', 2000, 'session-one'));
  tracker.handle(event('ended', 'two', 2000, 'session-two'));

  assert.deepEqual(transitions, ['started', 'started', 'ended', 'allEnded']);
  assert.deepEqual(tracker.snapshot(), { activeCount: 0, waitingCount: 0, runningCount: 0 });
});

test('keeps the first meaningful title and replaces only a generic title', () => {
  const transitions = [];
  const tracker = new TaskTracker((transition) => transitions.push(transition));
  tracker.handle({ ...event('started', 'turn-one'), title: 'Codex 附件任务' });
  tracker.handle({ ...event('running', 'turn-one', 2000), title: '整理发布说明' });
  tracker.handle({ ...event('started', 'turn-two', 3000), title: '继续处理' });
  assert.equal(tracker.getTasks()[0].title, '整理发布说明');

  tracker.handle(event('completed', 'turn-two', 4000));
  assert.equal(transitions.at(-1).task.title, '整理发布说明');
  assert.equal(transitions.at(-1).task.state, 'completed');
});

test('does not resurrect a terminal conversation from stale or unstarted lifecycle events', () => {
  const transitions = [];
  const tracker = new TaskTracker((transition) => transitions.push(transition.type));
  tracker.handle(event('started', 'ordered', 1000));
  tracker.handle(event('ended', 'ordered', 3000));
  tracker.handle(event('running', 'ordered', 2000));
  tracker.handle(event('running', 'ordered', 4000));

  assert.deepEqual(transitions, ['started', 'allEnded']);
  assert.equal(tracker.snapshot().activeCount, 0);

  tracker.handle(event('started', 'next', 5000));
  assert.equal(tracker.snapshot().activeCount, 1);
});

test('records an out-of-order terminal event before a task start arrives', () => {
  const tracker = new TaskTracker();
  tracker.handle(event('ended', 'late-start', 3000));
  tracker.handle(event('started', 'late-start', 2000));
  assert.equal(tracker.snapshot().activeCount, 0);

  tracker.handle(event('started', 'new-turn', 4000));
  assert.equal(tracker.snapshot().activeCount, 1);
});

test('a different explicit turn can start in the same millisecond as the previous terminal event', () => {
  const tracker = new TaskTracker();
  tracker.handle(event('ended', 'old-turn', 3000));
  tracker.handle(event('started', 'new-turn', 3000));

  assert.equal(tracker.snapshot().activeCount, 1);
  assert.equal(tracker.getTasks()[0].turnId, 'new-turn');

  const sameTurn = new TaskTracker();
  sameTurn.handle(event('ended', 'same-turn', 3000));
  sameTurn.handle(event('started', 'same-turn', 3000));
  assert.equal(sameTurn.snapshot().activeCount, 0);
});

test('older lifecycle events cannot regress a waiting task back to running', () => {
  const tracker = new TaskTracker();
  tracker.handle(event('started', 'waiting', 1000));
  tracker.handle(event('needs_input', 'waiting', 3000));
  tracker.handle(event('running', 'waiting', 2000));
  assert.equal(tracker.getTasks()[0].state, 'waiting');
});

test('restores trusted running and waiting snapshots without replaying start speech', () => {
  const transitions = [];
  const tracker = new TaskTracker((transition) => transitions.push(transition.type));
  const snapshot = tracker.restore([
    {
      ...event('running', 'running-turn', 3000, 'running-session'),
      title: '启动前已经开始',
      startedAt: 1000,
    },
    {
      ...event('needs_input', 'waiting-turn', 4000, 'waiting-session'),
      startedAt: 2000,
    },
  ]);

  assert.deepEqual(snapshot, { activeCount: 2, waitingCount: 1, runningCount: 1 });
  assert.deepEqual(transitions, []);
  assert.equal(tracker.getTasks().find((task) => task.key === 'codex:running-session').title, '启动前已经开始');
  assert.equal(tracker.getTasks().find((task) => task.key === 'codex:running-session').startedAt, 1000);
});

test('terminal events close a restored task and keep unknown outcomes neutral', () => {
  const transitions = [];
  const tracker = new TaskTracker((transition) => transitions.push(transition.type));
  tracker.restore([event('running', 'turn', 1000)]);
  tracker.handle(event('ended', 'turn', 2000));

  assert.deepEqual(transitions, ['allEnded']);
  assert.deepEqual(tracker.snapshot(), { activeCount: 0, waitingCount: 0, runningCount: 0 });
});

test('a newer restored lease supersedes an older terminal record', () => {
  const tracker = new TaskTracker();
  tracker.handle(event('ended', 'old-turn', 1000));
  tracker.restore([event('running', 'new-turn', 2000)]);

  assert.equal(tracker.snapshot().activeCount, 1);
  tracker.handle(event('needs_input', 'new-turn', 3000));
  assert.equal(tracker.getTasks()[0].state, 'waiting');
});

test('an authoritative active lease with a different turn survives a delayed terminal socket event', () => {
  const tracker = new TaskTracker();
  tracker.handle(event('ended', 'old-turn', 3000));
  tracker.restore([event('running', 'new-turn', 2000)]);

  assert.equal(tracker.snapshot().activeCount, 1);
  assert.equal(tracker.getTasks()[0].turnId, 'new-turn');
});

test('forgetting one disabled provider allows its unchanged active lease to be restored when re-enabled', () => {
  const tracker = new TaskTracker();
  const processed = new ProcessedAgentEvents();
  const codexLease = event('running', 'codex-turn', 2000, 'codex-session');
  const claudeLease = {
    ...event('running', 'claude-turn', 2000, 'claude-session'),
    provider: 'claude-code',
  };

  tracker.restore([codexLease, claudeLease]);
  processed.remember(codexLease);
  processed.remember(claudeLease);
  tracker.removeProvider('codex');
  processed.forgetProvider('codex');

  assert.equal(processed.has(codexLease), false);
  assert.equal(processed.has(claudeLease), true);
  if (!processed.has(codexLease)) tracker.restore([codexLease]);

  assert.equal(tracker.getTasks().some((task) => task.key === 'codex:codex-session'), true);
  assert.equal(tracker.getTasks().some((task) => task.key === 'claude-code:claude-session'), true);
});
