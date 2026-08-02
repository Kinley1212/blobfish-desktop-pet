function snapshotCpuTimes(cpus) {
  let idle = 0;
  let total = 0;
  for (const cpu of Array.isArray(cpus) ? cpus : []) {
    const times = cpu?.times || {};
    const values = ['user', 'nice', 'sys', 'idle', 'irq'].map((key) => Number(times[key]) || 0);
    idle += values[3];
    total += values.reduce((sum, value) => sum + value, 0);
  }
  return { idle, total };
}

function calculateSystemCpuPercent(previous, current) {
  if (!previous || !current) return null;
  const totalDelta = current.total - previous.total;
  const idleDelta = current.idle - previous.idle;
  if (!Number.isFinite(totalDelta) || totalDelta <= 0 || !Number.isFinite(idleDelta)) return null;
  return Math.max(0, Math.min(100, ((totalDelta - idleDelta) / totalDelta) * 100));
}

function summarizeAppMetrics(metrics) {
  let memoryKb = 0;
  let cpuPercent = 0;
  const processes = [];
  for (const metric of Array.isArray(metrics) ? metrics : []) {
    const workingSetKb = Math.max(0, Number(metric?.memory?.workingSetSize) || 0);
    const processCpuPercent = Math.max(0, Number(metric?.cpu?.percentCPUUsage) || 0);
    memoryKb += workingSetKb;
    cpuPercent += processCpuPercent;
    processes.push({
      type: String(metric?.type || 'Unknown'),
      memoryMb: workingSetKb / 1024,
      cpuPercent: processCpuPercent,
    });
  }
  return { memoryMb: memoryKb / 1024, cpuPercent, processes };
}

function buildPerformanceSample({ previousCpuTimes, cpus, systemMemory, appMetrics, now = Date.now() }) {
  const cpuTimes = snapshotCpuTimes(cpus);
  const systemCpuPercent = calculateSystemCpuPercent(previousCpuTimes, cpuTimes);
  const totalKb = Math.max(0, Number(systemMemory?.total) || 0);
  const freeKb = Math.max(0, Math.min(totalKb, Number(systemMemory?.free) || 0));
  const usedKb = Math.max(0, totalKb - freeKb);
  const appSummary = summarizeAppMetrics(appMetrics);
  return {
    sample: {
      timestamp: now,
      systemCpuPercent,
      systemMemoryUsedMb: usedKb / 1024,
      systemMemoryTotalMb: totalKb / 1024,
      systemMemoryPercent: totalKb > 0 ? (usedKb / totalKb) * 100 : null,
      appMemoryMb: appSummary.memoryMb,
      appCpuPercent: appSummary.cpuPercent,
      processes: appSummary.processes,
    },
    cpuTimes,
  };
}

module.exports = {
  buildPerformanceSample,
  calculateSystemCpuPercent,
  snapshotCpuTimes,
  summarizeAppMetrics,
};
