class SpeechQueue {
  constructor(deliver, options = {}) {
    if (typeof deliver !== 'function') throw new TypeError('SpeechQueue requires a deliver function');
    this.deliver = deliver;
    this.setTimer = options.setTimer || setTimeout;
    this.clearTimer = options.clearTimer || clearTimeout;
    this.pending = [];
    this.current = null;
    this.timer = null;
    this.sequence = 0;
  }

  enqueue(item) {
    if (!item || typeof item.text !== 'string' || item.text.length === 0) return false;
    const entry = {
      ...item,
      priority: Number.isFinite(item.priority) ? item.priority : 10,
      durationMs: Number.isFinite(item.durationMs) ? item.durationMs : 4000,
      sequence: this.sequence++,
    };

    if (entry.replaceKey) {
      this.pending = this.pending.filter((pending) => pending.replaceKey !== entry.replaceKey);
    }

    if (!this.current) {
      this.start(entry);
    } else if (entry.replaceKey && entry.replaceKey === this.current.replaceKey) {
      this.clearTimer(this.timer);
      this.timer = null;
      this.current = null;
      this.start(entry);
    } else if (entry.priority > this.current.priority) {
      this.clearTimer(this.timer);
      this.timer = null;
      this.current = null;
      this.start(entry);
    } else {
      this.pending.push(entry);
      this.pending.sort((a, b) => b.priority - a.priority || a.sequence - b.sequence);
    }
    return true;
  }

  start(entry) {
    this.current = entry;
    const { sequence: _sequence, ...message } = entry;
    this.deliver(message);
    this.timer = this.setTimer(() => {
      this.current = null;
      this.timer = null;
      const next = this.pending.shift();
      if (next) this.start(next);
    }, entry.durationMs);
  }

  clear() {
    if (this.timer) this.clearTimer(this.timer);
    this.timer = null;
    this.current = null;
    this.pending = [];
  }
}

module.exports = { SpeechQueue };
