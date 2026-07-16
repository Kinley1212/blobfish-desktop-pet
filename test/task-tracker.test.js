const test = require('node:test');
const assert = require('node:assert/strict');
const { TaskTracker } = require('../src/core/task-tracker');

function event(eventName, turnId, timestamp = 1000) {
  return { version: 1, provider: 'codex', event: eventName, sessionId: 'session', turnId, timestamp };
}

test('tracks multiple tasks, waiting state, single completion and all complete', () => {
  const transitions = [];
  const tracker = new TaskTracker((transition) => transitions.push(transition));
  tracker.handle(event('started', 'one'));
  tracker.handle(event('started', 'two'));
  tracker.handle(event('needs_input', 'one'));
  tracker.handle(event('needs_input', 'one'));
  tracker.handle(event('completed', 'one'));
  tracker.handle(event('completed', 'two'));

  assert.deepEqual(
    transitions.filter((transition) => transition.type !== 'state').map((transition) => transition.type),
    ['started', 'started', 'needsInput', 'completed', 'allCompleted'],
  );
  assert.deepEqual(tracker.snapshot(), { activeCount: 0, waitingCount: 0, runningCount: 0 });
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

test('hook stops end tasks without claiming successful completion', () => {
  const transitions = [];
  const tracker = new TaskTracker((transition) => transitions.push(transition.type));
  tracker.handle(event('started', 'one'));
  tracker.handle(event('started', 'two'));
  tracker.handle(event('ended', 'one'));
  tracker.handle(event('ended', 'two'));

  assert.deepEqual(transitions, ['started', 'started', 'ended', 'allEnded']);
  assert.deepEqual(tracker.snapshot(), { activeCount: 0, waitingCount: 0, runningCount: 0 });
});

test('keeps a task title when later lifecycle events omit it and exposes it on completion', () => {
  const transitions = [];
  const tracker = new TaskTracker((transition) => transitions.push(transition));
  tracker.handle({ ...event('started', 'titled'), title: '整理发布说明' });
  tracker.handle(event('running', 'titled', 2000));
  assert.equal(tracker.getTasks()[0].title, '整理发布说明');

  tracker.handle(event('completed', 'titled', 3000));
  assert.equal(transitions.at(-1).task.title, '整理发布说明');
  assert.equal(transitions.at(-1).task.state, 'completed');
});

test('accepts a title that first arrives on a later running event', () => {
  const tracker = new TaskTracker();
  tracker.handle(event('started', 'later'));
  tracker.handle({ ...event('running', 'later', 2000), title: '后来才有标题' });
  assert.equal(tracker.getTasks()[0].title, '后来才有标题');
});
