const { execFile } = require('child_process');

const VALID_STATUSES = new Set(['authorized', 'notDetermined', 'restricted', 'denied', 'writeOnly', 'unknown']);

function parseCalendarOutput(output) {
  let parsed;
  try {
    parsed = JSON.parse(output);
  } catch (error) {
    throw new Error(`Calendar helper returned invalid JSON: ${error.message}`);
  }
  if (!parsed || typeof parsed !== 'object' || !VALID_STATUSES.has(parsed.status)) {
    throw new Error('Calendar helper returned an invalid authorization status');
  }
  if (!Array.isArray(parsed.events) || parsed.events.length > 5000) {
    throw new Error('Calendar helper returned an invalid event list');
  }
  if (parsed.error !== undefined && parsed.error !== null && (
    typeof parsed.error !== 'string' || parsed.error.length > 500
  )) {
    throw new Error('Calendar helper returned an invalid error message');
  }

  const events = parsed.events.map((event) => {
    if (!event || typeof event !== 'object' || typeof event.id !== 'string' || event.id.length === 0 || event.id.length > 512) {
      throw new Error('Calendar helper returned an invalid event id');
    }
    if (typeof event.title !== 'string' || event.title.length > 240 || typeof event.allDay !== 'boolean') {
      throw new Error('Calendar helper returned invalid event metadata');
    }
    const start = new Date(event.start);
    const end = new Date(event.end);
    if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) || end < start) {
      throw new Error('Calendar helper returned invalid event dates');
    }
    return Object.freeze({ id: event.id, title: event.title, start, end, allDay: event.allDay });
  });

  return Object.freeze({ status: parsed.status, events: Object.freeze(events), error: parsed.error || null });
}

function readCalendar(helperPath, options = {}, execFileImpl = execFile) {
  const args = [options.requestAccess ? '--request-access' : '--status', '--minutes', String(options.horizonMinutes || 1440)];
  return new Promise((resolve, reject) => {
    execFileImpl(helperPath, args, {
      timeout: 30000,
      maxBuffer: 1024 * 1024,
      signal: options.signal,
    }, (error, stdout) => {
      if (error) {
        reject(new Error(`Calendar helper failed: ${error.message}`));
        return;
      }
      try {
        resolve(parseCalendarOutput(stdout));
      } catch (parseError) {
        reject(parseError);
      }
    });
  });
}

function dateKey(date) {
  return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`;
}

class CalendarService {
  constructor(options) {
    this.helperPath = options.helperPath;
    this.onEvent = options.onEvent;
    this.onStatus = options.onStatus || (() => {});
    this.read = options.read || ((readOptions) => readCalendar(this.helperPath, readOptions));
    this.now = options.now || (() => new Date());
    this.setInterval = options.setInterval || setInterval;
    this.clearInterval = options.clearInterval || clearInterval;
    this.pollIntervalMs = options.pollIntervalMs || 5 * 60 * 1000;
    this.tickIntervalMs = options.tickIntervalMs || 30 * 1000;
    this.enabled = false;
    this.accessAttempted = false;
    this.inFlight = false;
    this.events = [];
    this.notified = new Set();
    this.pollTimer = null;
    this.tickTimer = null;
    this.status = 'disabled';
    this.generation = 0;
    this.abortController = null;
  }

  setEnabled(enabled) {
    if (enabled === this.enabled) return;
    this.stop();
    this.enabled = enabled;
    if (!enabled) {
      this.status = 'disabled';
      this.onStatus(this.status);
      return;
    }

    this.accessAttempted = false;
    this.status = 'requesting';
    this.onStatus(this.status);
    this.poll();
    this.pollTimer = this.setInterval(() => this.poll(), this.pollIntervalMs);
    this.tickTimer = this.setInterval(() => this.evaluate(), this.tickIntervalMs);
  }

  async poll() {
    if (!this.enabled || this.inFlight) return;
    this.inFlight = true;
    const generation = this.generation;
    this.abortController = new AbortController();
    const requestAccess = !this.accessAttempted;
    this.accessAttempted = true;
    try {
      const result = await this.read({
        requestAccess,
        horizonMinutes: 1440,
        signal: this.abortController.signal,
      });
      if (!this.enabled || generation !== this.generation) return;
      this.status = result.status;
      this.events = result.status === 'authorized' ? [...result.events] : [];
      this.onStatus(this.status, result.error);
      if (this.status === 'authorized') {
        this.evaluate();
        this.evaluateBusyDay();
      }
    } catch (error) {
      if (!this.enabled || generation !== this.generation) return;
      this.status = 'error';
      this.onStatus(this.status, error.message);
    } finally {
      if (generation === this.generation) {
        this.inFlight = false;
        this.abortController = null;
      }
    }
  }

  evaluate(now = this.now()) {
    const currentMs = now.getTime();
    for (const event of this.events) {
      if (event.allDay) continue;
      const deltaMs = event.start.getTime() - currentMs;
      const baseKey = `${event.id}:${event.start.toISOString()}`;
      if (deltaMs <= 0 && deltaMs >= -90 * 1000) {
        const key = `starting:${baseKey}`;
        if (!this.notified.has(key)) {
          this.notified.add(key);
          this.notified.add(`upcoming:${baseKey}`);
          this.onEvent({ type: 'starting', event });
        }
      } else if (deltaMs > 0 && deltaMs <= 10 * 60 * 1000) {
        const key = `upcoming:${baseKey}`;
        if (!this.notified.has(key)) {
          this.notified.add(key);
          this.onEvent({ type: 'upcoming', event, minutes: Math.max(1, Math.ceil(deltaMs / 60000)) });
        }
      }
    }
  }

  evaluateBusyDay(now = this.now()) {
    const today = dateKey(now);
    const count = this.events.filter((event) => !event.allDay && dateKey(event.start) === today).length;
    const key = `busyDay:${today}`;
    if (count >= 5 && !this.notified.has(key)) {
      this.notified.add(key);
      this.onEvent({ type: 'busyDay', count });
    }
  }

  stop() {
    this.generation += 1;
    if (this.abortController) this.abortController.abort();
    if (this.pollTimer) this.clearInterval(this.pollTimer);
    if (this.tickTimer) this.clearInterval(this.tickTimer);
    this.pollTimer = null;
    this.tickTimer = null;
    this.events = [];
    this.inFlight = false;
    this.abortController = null;
    this.enabled = false;
  }
}

module.exports = {
  CalendarService,
  parseCalendarOutput,
  readCalendar,
};
