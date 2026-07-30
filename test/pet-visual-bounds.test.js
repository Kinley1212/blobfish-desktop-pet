const assert = require('node:assert/strict');
const test = require('node:test');

const {
  DEFAULT_EFFECT_RESERVE,
  calculateVisualTopOverflow,
} = require('../src/core/pet-visual-bounds');

test('art already inside the viewBox needs no extra native-window space', () => {
  const overflow = calculateVisualTopOverflow(
    { x: 0, y: 0, width: 140, height: 120 },
    { x: 4, y: 12, width: 132, height: 96 },
    { width: 105, height: 90 },
  );

  assert.equal(overflow, 0);
});

test('a hat extending above the viewBox reserves its full visible height', () => {
  const overflow = calculateVisualTopOverflow(
    { x: 0, y: 0, width: 140, height: 120 },
    { x: 4, y: -30, width: 132, height: 138 },
    { width: 105, height: 90 },
  );

  assert.equal(overflow, DEFAULT_EFFECT_RESERVE + 22.5);
});

test('viewBox aspect-ratio centering is included in the top measurement', () => {
  const overflow = calculateVisualTopOverflow(
    { x: 0, y: 0, width: 100, height: 100 },
    { x: 0, y: -10, width: 100, height: 110 },
    { width: 200, height: 100 },
    5,
  );

  // The 100x100 viewBox is centred inside a 200x100 viewport, so its top has
  // no vertical letterboxing and the -10 coordinate becomes -10 px.
  assert.equal(overflow, 15);
});

test('a timer layout that lifts the whole pet is included in the overflow', () => {
  const overflow = calculateVisualTopOverflow(
    { x: 0, y: 0, width: 140, height: 120 },
    { x: 0, y: 12, width: 140, height: 96 },
    { width: 105, height: 90, topShift: -42 },
  );

  assert.equal(overflow, DEFAULT_EFFECT_RESERVE + 42 - 9);
});

test('visual-bound calculations reject malformed geometry', () => {
  assert.throws(
    () => calculateVisualTopOverflow(
      { x: 0, y: 0, width: 0, height: 100 },
      { y: 0 },
      { width: 100, height: 100 },
    ),
    /invalid/,
  );
  assert.throws(
    () => calculateVisualTopOverflow(
      { x: 0, y: 0, width: 100, height: 100 },
      { y: Number.NaN },
      { width: 100, height: 100 },
    ),
    /finite/,
  );
});
