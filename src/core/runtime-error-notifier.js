const DEFAULT_COOLDOWN_MS = 5 * 60 * 1000;

class RuntimeErrorNotifier {
  constructor(notify, options = {}) {
    if (typeof notify !== 'function') throw new TypeError('RuntimeErrorNotifier requires a notify function');
    this.notify = notify;
    this.log = options.log || console.error;
    this.now = options.now || Date.now;
    this.cooldownMs = options.cooldownMs ?? DEFAULT_COOLDOWN_MS;
    this.ready = false;
    this.pending = false;
    this.lastNotifiedAt = null;
  }

  setReady(ready = true) {
    this.ready = ready;
    return this.flush();
  }

  report(scope, error) {
    const detail = error instanceof Error ? error.message : String(error);
    this.log(`${scope}: ${detail}`);
    this.pending = true;
    return this.flush();
  }

  flush() {
    if (!this.ready || !this.pending) return false;
    this.pending = false;

    const now = this.now();
    if (this.lastNotifiedAt !== null && now - this.lastNotifiedAt < this.cooldownMs) return false;
    const notified = this.notify();
    if (notified) this.lastNotifiedAt = now;
    return notified;
  }
}

module.exports = { DEFAULT_COOLDOWN_MS, RuntimeErrorNotifier };
