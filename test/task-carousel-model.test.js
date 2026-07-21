const test = require('node:test');
const assert = require('node:assert/strict');
const { buildCarouselLayout, nextTaskKey } = require('../src/core/task-carousel-model');

const tasks = ['one', 'two', 'three', 'four', 'five'].map((taskKey) => ({ taskKey }));

test('carousel layout reports the front position and exposes three rear cards', () => {
  const layout = buildCarouselLayout(tasks, 'two');
  assert.equal(layout.frontTaskKey, 'two');
  assert.equal(layout.position, 2);
  assert.equal(layout.total, 5);
  assert.deepEqual(
    layout.entries.filter((entry) => entry.visible).map((entry) => [entry.item.taskKey, entry.depth]),
    [['two', 0], ['three', 1], ['four', 2], ['five', 3]],
  );
});

test('carousel layout falls back safely and rotates in a stable cycle', () => {
  assert.equal(buildCarouselLayout(tasks, 'missing').frontTaskKey, 'one');
  assert.equal(nextTaskKey(tasks, 'one'), 'two');
  assert.equal(nextTaskKey(tasks, 'five'), 'one');
  assert.equal(nextTaskKey([], 'one'), null);
});
