const DEFAULT_GUARD_TIMING = Object.freeze({
  graceMs: 5 * 60 * 1000,
  sustainedMs: 3 * 60 * 1000,
  emergencySustainedMs: 60 * 1000,
  emergencyMultiplier: 1.5,
});

class MemoryGuard {
  constructor(options = {}) {
    this.timing = { ...DEFAULT_GUARD_TIMING, ...options };
    this.startedAt = Number.isFinite(options.startedAt) ? options.startedAt : Date.now();
    this.highSince = null;
    this.emergencySince = null;
  }

  resetPressure() {
    this.highSince = null;
    this.emergencySince = null;
  }

  evaluate(sample, config, blockers = {}, now = Date.now()) {
    if (!config?.enabled) {
      this.resetPressure();
      return { action: 'none', reason: 'disabled' };
    }
    if (now - this.startedAt < this.timing.graceMs) return { action: 'none', reason: 'grace' };

    const memoryMb = Number(sample?.appMemoryMb);
    const limitMb = Number(config.limitMb);
    if (!Number.isFinite(memoryMb) || !Number.isFinite(limitMb) || limitMb <= 0) {
      this.resetPressure();
      return { action: 'none', reason: 'invalid-sample' };
    }
    if (memoryMb < limitMb) {
      this.resetPressure();
      return { action: 'none', reason: 'below-limit' };
    }

    if (this.highSince === null) this.highSince = now;
    const emergencyLimitMb = limitMb * this.timing.emergencyMultiplier;
    if (memoryMb >= emergencyLimitMb) {
      if (this.emergencySince === null) this.emergencySince = now;
    } else {
      this.emergencySince = null;
    }

    const updateBlocked = Boolean(blockers.updateInstalling);
    const normalBlocked = updateBlocked || Boolean(
      blockers.settingsOpen
      || blockers.clockOpen
      || blockers.dialogueOpen
      || blockers.alarmRinging,
    );
    if (this.emergencySince !== null && now - this.emergencySince >= this.timing.emergencySustainedMs) {
      return updateBlocked
        ? { action: 'deferred', reason: 'update-installing' }
        : { action: 'quit', reason: 'emergency', memoryMb, limitMb };
    }
    if (now - this.highSince >= this.timing.sustainedMs) {
      return normalBlocked
        ? { action: 'deferred', reason: 'busy' }
        : { action: 'quit', reason: 'sustained', memoryMb, limitMb };
    }
    return { action: 'none', reason: 'observing' };
  }
}

module.exports = { DEFAULT_GUARD_TIMING, MemoryGuard };
