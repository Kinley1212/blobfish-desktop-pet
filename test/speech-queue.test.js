const test = require('node:test');
const assert = require('node:assert/strict');
const { SpeechQueue } = require('../src/core/speech-queue');

function createFakeTimers() {
  const timers = [];
  return {
    timers,
    setTimer(callback) {
      const timer = { callback, cleared: false };
      timers.push(timer);
      return timer;
    },
    clearTimer(timer) {
      timer.cleared = true;
    },
    runNext() {
      const timer = timers.find((entry) => !entry.cleared && !entry.ran);
      timer.ran = true;
      timer.callback();
    },
  };
}

test('higher-priority speech preempts current speech and queued items stay ordered', () => {
  const delivered = [];
  const fake = createFakeTimers();
  const queue = new SpeechQueue((item) => delivered.push(item.text), fake);

  queue.enqueue({ text: 'idle', priority: 10 });
  queue.enqueue({ text: 'schedule', priority: 40 });
  queue.enqueue({ text: 'click', priority: 30 });
  assert.deepEqual(delivered, ['idle', 'schedule']);

  fake.runNext();
  assert.deepEqual(delivered, ['idle', 'schedule', 'click']);
});

test('replaceKey prevents rapid clicks from filling the queue', () => {
  const delivered = [];
  const fake = createFakeTimers();
  const queue = new SpeechQueue((item) => delivered.push(item.text), fake);

  queue.enqueue({ text: 'first', priority: 30, replaceKey: 'click' });
  queue.enqueue({ text: 'second', priority: 30, replaceKey: 'click' });
  queue.enqueue({ text: 'third', priority: 30, replaceKey: 'click' });
  assert.deepEqual(delivered, ['first', 'second', 'third']);
  assert.equal(queue.pending.length, 0);
});
