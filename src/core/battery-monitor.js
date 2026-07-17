const { execFile } = require('child_process');

const DEFAULT_THRESHOLDS = Object.freeze([20, 10, 5, 3, 2]);

function parsePmsetBattery(output) {
  if (typeof output !== 'string') throw new Error('pmset output must be text');
  const sourceMatch = output.match(/Now drawing from '([^']+)'/);
  const percentageMatch = output.match(/\b(\d{1,3})%/);
  if (!sourceMatch || !percentageMatch) throw new Error('Unable to parse battery status from pmset');

  const percentage = Number(percentageMatch[1]);
  if (!Number.isInteger(percentage) || percentage < 0 || percentage > 100) {
    throw new Error('pmset returned an invalid battery percentage');
  }
  const lower = output.toLowerCase();
  return {
    percentage,
    powerSource: sourceMatch[1],
    onBattery: sourceMatch[1].toLowerCase().includes('battery'),
    charging: lower.includes('; charging;') || lower.includes('; charged;'),
  };
}

function readMacBattery(execFileImpl = execFile) {
  return new Promise((resolve, reject) => {
    execFileImpl('/usr/bin/pmset', ['-g', 'batt'], { timeout: 5000, maxBuffer: 64 * 1024 }, (error, stdout) => {
      if (error) {
        reject(new Error(`Unable to read battery status: ${error.message}`));
        return;
      }
      try {
        resolve(parsePmsetBattery(stdout));
      } catch (parseError) {
        reject(parseError);
      }
    });
  });
}

class BatteryThresholdTracker {
  constructor(onThreshold, thresholds = DEFAULT_THRESHOLDS) {
    if (typeof onThreshold !== 'function') throw new TypeError('BatteryThresholdTracker requires a callback');
    this.onThreshold = onThreshold;
    this.thresholds = [...thresholds].sort((a, b) => b - a);
    this.notified = new Set();
  }

  update(sample) {
    if (!sample || !Number.isInteger(sample.percentage)) return null;
    if (!sample.onBattery) {
      this.notified.clear();
      return null;
    }

    const crossed = this.thresholds.filter((threshold) => sample.percentage <= threshold && !this.notified.has(threshold));
    if (crossed.length === 0) return null;
    for (const threshold of crossed) this.notified.add(threshold);
    const selected = Math.min(...crossed);
    this.onThreshold(selected, sample);
    return selected;
  }
}

module.exports = {
  BatteryThresholdTracker,
  DEFAULT_THRESHOLDS,
  parsePmsetBattery,
  readMacBattery,
};
