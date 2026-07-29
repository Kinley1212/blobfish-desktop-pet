const { execFile } = require('child_process');

const VALID_STATUSES = new Set(['authorized', 'notDetermined', 'restricted', 'denied', 'writeOnly', 'unknown']);
const DEFAULT_MAX_NOTIFIED_ENTRIES = 12_000;
const DEFAULT_NOTIFICATION_RETENTION_MS = 48 * 60 * 60 * 1000;
const DEFAULT_WAKE_CATCH_UP_MS = 5 * 60 * 1000;
const STARTING_GRACE_MS = 90 * 1000;

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
    this.maxNotifiedEntries = Number.isSafeInteger(options.maxNotifiedEntries)
      && options.maxNotifiedEntries > 0
      ? options.maxNotifiedEntries
      : DEFAULT_MAX_NOTIFIED_ENTRIES;
    this.notificationRetentionMs = Number.isFinite(options.notificationRetentionMs)
      && options.notificationRetentionMs > 0
      ? options.notificationRetentionMs
      : DEFAULT_NOTIFICATION_RETENTION_MS;
    this.wakeCatchUpMs = Number.isFinite(options.wakeCatchUpMs)
      && options.wakeCatchUpMs > 0
      ? options.wakeCatchUpMs
      : DEFAULT_WAKE_CATCH_UP_MS;
    this.enabled = false;
    this.accessAttempted = false;
    this.inFlight = false;
    this.events = [];
    this.notified = new Map();
    this.pollTimer = null;
    this.tickTimer = null;
    this.status = 'disabled';
    this.generation = 0;
    this.abortController = null;
    this.lastEvaluatedAt = null;
    this.pendingWakeCatchUpSinceMs = null;
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
        const evaluationNow = this.now();
        const startingSinceMs = this.pendingWakeCatchUpSinceMs;
        this.pendingWakeCatchUpSinceMs = null;
        this.evaluate(evaluationNow, { startingSinceMs });
        this.evaluateBusyDay(evaluationNow);
      } else {
        this.pendingWakeCatchUpSinceMs = null;
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

  pruneNotified(nowMs) {
    const oldestAllowed = nowMs - this.notificationRetentionMs;
    for (const [key, notifiedAt] of this.notified) {
      if (Number.isFinite(notifiedAt) && notifiedAt >= oldestAllowed) continue;
      this.notified.delete(key);
    }
    while (this.notified.size > this.maxNotifiedEntries) {
      this.notified.delete(this.notified.keys().next().value);
    }
  }

  rememberNotification(key, nowMs) {
    if (this.notified.has(key)) return false;
    this.notified.set(key, nowMs);
    this.pruneNotified(nowMs);
    return true;
  }

  evaluate(now = this.now(), options = {}) {
    const currentMs = now.getTime();
    if (!Number.isFinite(currentMs)) throw new TypeError('Calendar evaluation requires a valid date');
    this.pruneNotified(currentMs);
    const requestedStartingSinceMs = options.startingSinceMs;
    const startingSinceMs = Number.isFinite(requestedStartingSinceMs)
      ? Math.max(currentMs - this.wakeCatchUpMs, Math.min(currentMs, requestedStartingSinceMs))
      : currentMs - STARTING_GRACE_MS;
    for (const event of this.events) {
      if (event.allDay) continue;
      const deltaMs = event.start.getTime() - currentMs;
      const baseKey = `${event.id}:${event.start.toISOString()}`;
      if (deltaMs <= 0 && event.start.getTime() >= startingSinceMs) {
        const key = `starting:${baseKey}`;
        if (!this.notified.has(key)) {
          this.rememberNotification(`upcoming:${baseKey}`, currentMs);
          this.rememberNotification(key, currentMs);
          this.onEvent({ type: 'starting', event });
        }
      } else if (deltaMs > 0 && deltaMs <= 10 * 60 * 1000) {
        const key = `upcoming:${baseKey}`;
        if (this.rememberNotification(key, currentMs)) {
          this.onEvent({ type: 'upcoming', event, minutes: Math.max(1, Math.ceil(deltaMs / 60000)) });
        }
      }
    }
    this.lastEvaluatedAt = currentMs;
  }

  evaluateBusyDay(now = this.now()) {
    const currentMs = now.getTime();
    if (!Number.isFinite(currentMs)) throw new TypeError('Calendar evaluation requires a valid date');
    this.pruneNotified(currentMs);
    const today = dateKey(now);
    const count = this.events.filter((event) => !event.allDay && dateKey(event.start) === today).length;
    const key = `busyDay:${today}`;
    if (count >= 5 && this.rememberNotification(key, currentMs)) {
      this.onEvent({ type: 'busyDay', count });
    }
  }

  refreshAfterWake(now = this.now(), inactiveSince = null) {
    if (!this.enabled) return Promise.resolve(false);
    const currentMs = now.getTime();
    if (!Number.isFinite(currentMs)) {
      return Promise.reject(new TypeError('Calendar wake refresh requires a valid date'));
    }
    const inactiveSinceMs = inactiveSince instanceof Date
      ? inactiveSince.getTime()
      : (Number.isFinite(inactiveSince) ? inactiveSince : null);
    const fallbackSinceMs = Number.isFinite(this.lastEvaluatedAt)
      ? this.lastEvaluatedAt
      : currentMs - STARTING_GRACE_MS;
    const requestedSinceMs = Number.isFinite(inactiveSinceMs) ? inactiveSinceMs : fallbackSinceMs;
    const startingSinceMs = Math.max(
      currentMs - this.wakeCatchUpMs,
      Math.min(currentMs, requestedSinceMs),
    );
    this.pendingWakeCatchUpSinceMs = Number.isFinite(this.pendingWakeCatchUpSinceMs)
      ? Math.min(this.pendingWakeCatchUpSinceMs, startingSinceMs)
      : startingSinceMs;

    if (this.abortController) {
      this.generation += 1;
      this.abortController.abort();
      this.abortController = null;
      this.inFlight = false;
    }
    return this.poll().then(() => true);
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
    this.lastEvaluatedAt = null;
    this.pendingWakeCatchUpSinceMs = null;
    this.enabled = false;
  }
}

module.exports = {
  CalendarService,
  parseCalendarOutput,
  readCalendar,
};
