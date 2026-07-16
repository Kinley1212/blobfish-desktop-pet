const assert = require('node:assert/strict');
const test = require('node:test');

const { calculateVerticalPlacement } = require('../src/core/pet-boundary');

const bounds = { minY: 25, maxY: 925 };
const metrics = { height: 90, topMargin: 110 };

test('pet moves inside its transparent window until its body reaches the menu bar', () => {
  assert.deepEqual(calculateVerticalPlacement(25, bounds, metrics), {
    petTop: 25,
    windowY: 25,
    topOffset: 0,
    hitTop: true,
    hitBottom: false,
  });
  assert.deepEqual(calculateVerticalPlacement(75, bounds, metrics), {
    petTop: 75,
    windowY: 25,
    topOffset: 50,
    hitTop: false,
    hitBottom: false,
  });
});

test('pet uses its normal bottom anchor away from the top and still stops above the Dock', () => {
  assert.deepEqual(calculateVerticalPlacement(155, bounds, metrics), {
    petTop: 155,
    windowY: 45,
    topOffset: 110,
    hitTop: false,
    hitBottom: false,
  });
  assert.deepEqual(calculateVerticalPlacement(900, bounds, metrics), {
    petTop: 835,
    windowY: 725,
    topOffset: 110,
    hitTop: false,
    hitBottom: true,
  });
});

test('pet boundary calculations reject invalid geometry', () => {
  assert.throws(() => calculateVerticalPlacement(Number.NaN, bounds, metrics), /finite/);
  assert.throws(() => calculateVerticalPlacement(100, { minY: 10, maxY: 10 }, metrics), /invalid/);
});
