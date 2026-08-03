function snapshotCpuTimes(cpus) {
  let idle = 0;
  let total = 0;
  const processors = Array.isArray(cpus) ? cpus : [];
  for (const cpu of processors) {
    const times = cpu?.times || {};
    const values = ['user', 'nice', 'sys', 'idle', 'irq'].map((key) => Number(times[key]) || 0);
    idle += values[3];
    total += values.reduce((sum, value) => sum + value, 0);
  }
  return { idle, total, logicalProcessorCount: processors.length };
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

function normalizeAppCpuPercent(cpuPercent, logicalProcessorCount) {
  const value = Math.max(0, Number(cpuPercent) || 0);
  const processors = Math.max(1, Math.floor(Number(logicalProcessorCount) || 1));
  return Math.min(100, value / processors);
}

function calculateSystemMemory(systemMemory) {
  const totalKb = Math.max(0, Number(systemMemory?.total) || 0);
  const freeKb = Math.max(0, Math.min(totalKb, Number(systemMemory?.free) || 0));
  const fileBackedKb = Math.max(0, Number(systemMemory?.fileBacked) || 0);
  const purgeableKb = Math.max(0, Number(systemMemory?.purgeable) || 0);
  const reclaimableKb = Math.min(totalKb - freeKb, fileBackedKb + purgeableKb);
  const usedKb = Math.max(0, totalKb - freeKb - reclaimableKb);
  return { totalKb, usedKb, percent: totalKb > 0 ? (usedKb / totalKb) * 100 : null };
}

function buildPerformanceSample({ previousCpuTimes, cpus, systemMemory, appMetrics, now = Date.now() }) {
  const cpuTimes = snapshotCpuTimes(cpus);
  const systemCpuPercent = calculateSystemCpuPercent(previousCpuTimes, cpuTimes);
  const memory = calculateSystemMemory(systemMemory);
  const appSummary = summarizeAppMetrics(appMetrics);
  return {
    sample: {
      timestamp: now,
      systemCpuPercent,
      systemMemoryUsedMb: memory.usedKb / 1024,
      systemMemoryTotalMb: memory.totalKb / 1024,
      systemMemoryPercent: memory.percent,
      appMemoryMb: appSummary.memoryMb,
      appCpuPercent: normalizeAppCpuPercent(appSummary.cpuPercent, cpuTimes.logicalProcessorCount),
      processes: appSummary.processes,
    },
    cpuTimes,
  };
}

module.exports = {
  buildPerformanceSample,
  calculateSystemMemory,
  calculateSystemCpuPercent,
  normalizeAppCpuPercent,
  snapshotCpuTimes,
  summarizeAppMetrics,
};
