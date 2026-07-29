const test = require('node:test');
const assert = require('node:assert/strict');
const { TaskLeasePollEpoch } = require('../src/core/task-lease-poll-epoch');
const { ProcessedAgentEvents, TaskTracker } = require('../src/core/task-tracker');

function event(eventName, turnId, timestamp) {
  return {
    version: 1,
    provider: 'codex',
    event: eventName,
    sessionId: 'session',
    turnId,
    timestamp,
  };
}

test('socket terminal invalidates an in-flight stale active scan before it can restore the task', async () => {
  const tracker = new TaskTracker();
  const processed = new ProcessedAgentEvents();
  const pollEpoch = new TaskLeasePollEpoch();
  const staleActive = event('running', 'stale-active-turn', 2000);
  const terminal = event('ended', 'socket-terminal-turn', 3000);
  let finishScan;
  const scanPaused = new Promise((resolve) => {
    finishScan = resolve;
  });
  let scanStarted;
  const scanHasStarted = new Promise((resolve) => {
    scanStarted = resolve;
  });

  const applyRecords = (records) => {
    for (const record of records) {
      if (processed.has(record.event)) continue;
      if (['ended', 'completed', 'failed'].includes(record.event.event)) {
        tracker.handle(record.event);
      } else {
        tracker.restore([record.event]);
      }
      processed.remember(record.event);
    }
  };

  const firstPoll = pollEpoch.scanAndApply(
    async () => {
      const openedSnapshot = [{ event: staleActive }];
      scanStarted();
      await scanPaused;
      return openedSnapshot;
    },
    applyRecords,
  );

  await scanHasStarted;
  pollEpoch.invalidate();
  tracker.handle(terminal);
  processed.remember(terminal);
  finishScan();

  assert.equal(await firstPoll, false);
  assert.equal(tracker.snapshot().activeCount, 0);
  assert.equal(processed.has(staleActive), false);

  const secondPoll = await pollEpoch.scanAndApply(
    async () => [{ event: terminal }],
    applyRecords,
  );

  assert.equal(secondPoll, true);
  assert.equal(tracker.snapshot().activeCount, 0);
  assert.equal(processed.has(terminal), true);
  assert.equal(processed.has(staleActive), false);
});
