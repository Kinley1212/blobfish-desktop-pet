const test = require('node:test');
const assert = require('node:assert/strict');
const {
  buildPerformanceSample,
  calculateSystemMemory,
  calculateSystemCpuPercent,
  normalizeAppCpuPercent,
  summarizeAppMetrics,
} = require('../src/core/performance-monitor');

test('CPU usage is derived from cumulative idle and total deltas', () => {
  assert.equal(calculateSystemCpuPercent({ idle: 800, total: 1000 }, { idle: 850, total: 1100 }), 50);
  assert.equal(calculateSystemCpuPercent(null, { idle: 1, total: 2 }), null);
});

test('app metrics combine every Electron process without titles or command lines', () => {
  const summary = summarizeAppMetrics([
    { type: 'Browser', memory: { workingSetSize: 102400 }, cpu: { percentCPUUsage: 2 } },
    { type: 'Tab', memory: { workingSetSize: 51200 }, cpu: { percentCPUUsage: 3 } },
  ]);
  assert.equal(summary.memoryMb, 150);
  assert.equal(summary.cpuPercent, 5);
  assert.deepEqual(summary.processes, [
    { type: 'Browser', memoryMb: 100, cpuPercent: 2 },
    { type: 'Tab', memoryMb: 50, cpuPercent: 3 },
  ]);
});

test('app CPU uses the same whole-machine capacity as system CPU', () => {
  assert.equal(normalizeAppCpuPercent(34, 8), 4.25);
  assert.equal(normalizeAppCpuPercent(240, 8), 30);
  assert.equal(normalizeAppCpuPercent(34, 0), 34);
});

test('system memory excludes reclaimable macOS cache', () => {
  const memory = calculateSystemMemory({
    total: 16 * 1024 * 1024,
    free: 0.46 * 1024 * 1024,
    fileBacked: 3.10 * 1024 * 1024,
    purgeable: 0.06 * 1024 * 1024,
  });
  assert.ok(Math.abs(memory.usedKb / 1024 / 1024 - 12.38) < 0.001);
  assert.ok(Math.abs(memory.percent - 77.375) < 0.001);
});

test('performance sample reports bounded percentages and memory in MB', () => {
  const result = buildPerformanceSample({
    previousCpuTimes: { idle: 100, total: 200 },
    cpus: [
      { times: { user: 100, nice: 0, sys: 20, idle: 180, irq: 0 } },
      { times: { user: 100, nice: 0, sys: 20, idle: 180, irq: 0 } },
    ],
    systemMemory: { total: 16 * 1024 * 1024, free: 4 * 1024 * 1024 },
    appMetrics: [{ type: 'Browser', memory: { workingSetSize: 204800 }, cpu: { percentCPUUsage: 1 } }],
    now: 123,
  });
  assert.equal(result.sample.timestamp, 123);
  assert.equal(result.sample.systemMemoryTotalMb, 16 * 1024);
  assert.equal(result.sample.systemMemoryPercent, 75);
  assert.equal(result.sample.appMemoryMb, 200);
  assert.equal(result.sample.appCpuPercent, 0.5);
});
