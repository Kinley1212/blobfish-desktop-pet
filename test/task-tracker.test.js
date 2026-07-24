const test = require('node:test');
const assert = require('node:assert/strict');
const { TaskTracker } = require('../src/core/task-tracker');

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

test('a stale stop from the previous turn cannot close the current turn', () => {
  const tracker = new TaskTracker();
  tracker.handle(event('started', 'turn-one', 1000));
  tracker.handle(event('started', 'turn-two', 2000));
  tracker.handle(event('ended', 'turn-one', 3000));

  assert.equal(tracker.snapshot().activeCount, 1);
  assert.equal(tracker.getTasks()[0].turnId, 'turn-two');
});

test('an unfamiliar terminal turn id still closes the active conversation', () => {
  const tracker = new TaskTracker();
  tracker.handle(event('started', 'turn-one', 1000));
  tracker.handle(event('ended', 'normalized-stop-id', 2000));

  assert.equal(tracker.snapshot().activeCount, 0);
});

test('remembers several superseded turns so delayed stops cannot close the latest turn', () => {
  const tracker = new TaskTracker();
  tracker.handle(event('started', 'turn-one', 1000));
  tracker.handle(event('started', 'turn-two', 2000));
  tracker.handle(event('started', 'turn-three', 3000));
  tracker.handle(event('ended', 'turn-one', 4000));
  tracker.handle(event('ended', 'turn-two', 5000));

  assert.equal(tracker.snapshot().activeCount, 1);
  assert.equal(tracker.getTasks()[0].turnId, 'turn-three');
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

test('older lifecycle events cannot regress a waiting task back to running', () => {
  const tracker = new TaskTracker();
  tracker.handle(event('started', 'waiting', 1000));
  tracker.handle(event('needs_input', 'waiting', 3000));
  tracker.handle(event('running', 'waiting', 2000));
  assert.equal(tracker.getTasks()[0].state, 'waiting');
});
