const test = require('node:test');
const assert = require('node:assert/strict');
const { BatteryThresholdTracker, parsePmsetBattery } = require('../src/core/battery-monitor');

test('parses macOS pmset battery output without a shell', () => {
  const sample = parsePmsetBattery("Now drawing from 'Battery Power'\n -InternalBattery-0\t3%; discharging; 0:07 remaining present: true\n");
  assert.deepEqual(sample, {
    percentage: 3,
    powerSource: 'Battery Power',
    onBattery: true,
    charging: false,
  });
});

test('alerts once per discharge cycle and chooses 2% when 3% was skipped', () => {
  const alerts = [];
  const tracker = new BatteryThresholdTracker((threshold) => alerts.push(threshold));
  tracker.update({ percentage: 19, onBattery: true });
  tracker.update({ percentage: 19, onBattery: true });
  tracker.update({ percentage: 9, onBattery: true });
  tracker.update({ percentage: 4, onBattery: true });
  tracker.update({ percentage: 2, onBattery: true });
  tracker.update({ percentage: 2, onBattery: true });
  assert.deepEqual(alerts, [20, 10, 5, 2]);

  tracker.update({ percentage: 60, onBattery: false });
  tracker.update({ percentage: 3, onBattery: true });
  assert.deepEqual(alerts, [20, 10, 5, 2, 3]);
});
