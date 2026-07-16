const assert = require('node:assert/strict');
const test = require('node:test');

const {
  advanceFractionalCoordinate,
  roundWindowCoordinate,
} = require('../src/core/fractional-position');

function walk(start, delta, ticks) {
  let precise = start;
  let native = start;
  for (let tick = 0; tick < ticks; tick += 1) {
    precise = advanceFractionalCoordinate(precise, native, delta);
    native = roundWindowCoordinate(precise);
  }
  return { precise, native };
}

test('quarter-pixel speed accumulates into visible movement in both directions', () => {
  assert.equal(walk(100, 0.25, 4).native, 101);
  assert.equal(walk(100, -0.25, 4).native, 99);
});

test('fractional movement keeps equal long-term distance in both directions', () => {
  assert.equal(walk(100, 0.5, 20).precise, 110);
  assert.equal(walk(100, -0.5, 20).precise, 90);
  assert.equal(walk(100, 1.5, 20).precise, 130);
  assert.equal(walk(100, -1.5, 20).precise, 70);
});

test('external native movement resets a stale fractional accumulator', () => {
  assert.equal(advanceFractionalCoordinate(100.25, 140, 0.25), 140.25);
  assert.equal(roundWindowCoordinate(-0.5), 0);
});
