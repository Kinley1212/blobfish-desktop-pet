const TEST_TIMEOUT_MS = 60 * 1000;
const PROVIDERS = new Set(['codex', 'claude']);

function assertProvider(provider) {
  if (!PROVIDERS.has(provider)) throw new Error('不支持的代理连接类型');
}

class ConnectionHealthTracker {
  constructor(options = {}) {
    this.now = options.now || Date.now;
    this.testTimeoutMs = options.testTimeoutMs || TEST_TIMEOUT_MS;
    this.records = new Map();
  }

  getRecord(provider) {
    assertProvider(provider);
    if (!this.records.has(provider)) {
      this.records.set(provider, { lastEventAt: null, testStartedAt: null });
    }
    return this.records.get(provider);
  }

  startTest(provider) {
    const record = this.getRecord(provider);
    record.testStartedAt = this.now();
    return this.snapshot(provider);
  }

  noteEvent(provider) {
    const record = this.getRecord(provider);
    record.lastEventAt = this.now();
    record.testStartedAt = null;
    return this.snapshot(provider);
  }

  clear(provider) {
    assertProvider(provider);
    this.records.delete(provider);
    return this.snapshot(provider);
  }

  snapshot(provider) {
    const record = this.getRecord(provider);
    const now = this.now();
    let health = 'unverified';
    let testExpiresAt = null;
    if (record.testStartedAt !== null) {
      testExpiresAt = record.testStartedAt + this.testTimeoutMs;
      health = now < testExpiresAt ? 'awaiting-event' : 'test-timeout';
    } else if (record.lastEventAt !== null) {
      health = 'active';
    }
    return Object.freeze({
      provider,
      health,
      lastEventAt: record.lastEventAt,
      testStartedAt: record.testStartedAt,
      testExpiresAt,
    });
  }

  decorate(provider, installation) {
    const snapshot = this.snapshot(provider);
    if (installation.state !== 'connected') {
      return Object.freeze({ ...installation, ...snapshot, health: 'unavailable' });
    }
    return Object.freeze({ ...installation, ...snapshot });
  }
}

module.exports = { ConnectionHealthTracker, TEST_TIMEOUT_MS };
