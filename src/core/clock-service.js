const crypto = require('crypto');
const {
  DEFAULT_CATCH_UP_MS,
  createAlarm,
  createTimer,
  getNextDueAt,
  reconcileClockState,
  validateAlarm,
  validateClockState,
  validatePreferences,
} = require('./clock-engine');

const MAX_SCHEDULER_DELAY_MS = 30 * 1000;
const MIN_SCHEDULER_DELAY_MS = 100;

class ClockService {
  constructor(store, options = {}) {
    if (!store || typeof store.load !== 'function' || typeof store.save !== 'function') {
      throw new TypeError('ClockService requires a clock store');
    }
    this.store = store;
    this.now = options.now || Date.now;
    this.setTimeout = options.setTimeout || setTimeout;
    this.clearTimeout = options.clearTimeout || clearTimeout;
    this.makeId = options.makeId || (() => crypto.randomUUID());
    this.getWorkdays = options.getWorkdays || (() => [1, 2, 3, 4, 5]);
    this.onChange = options.onChange || (() => {});
    this.onDue = options.onDue || (() => {});
    this.onMissed = options.onMissed || (() => {});
    this.catchUpMs = options.catchUpMs ?? DEFAULT_CATCH_UP_MS;
    this.timerHandle = null;
    this.running = false;
    this.state = validateClockState(this.store.get ? this.store.get() : this.store.load());
  }

  start() {
    if (this.running) return this.getState();
    this.running = true;
    this.state = this.store.load();
    this.reconcile();
    return this.getState();
  }

  stop() {
    this.running = false;
    if (this.timerHandle !== null) this.clearTimeout(this.timerHandle);
    this.timerHandle = null;
  }

  getState() {
    return JSON.parse(JSON.stringify(this.state));
  }

  persist(nextState, options = {}) {
    this.state = this.store.save(nextState);
    this.onChange(this.getState(), options);
    this.arm();
    return this.getState();
  }

  arm() {
    if (this.timerHandle !== null) this.clearTimeout(this.timerHandle);
    this.timerHandle = null;
    if (!this.running) return;
    const nowMs = this.now();
    const nextDueAt = getNextDueAt(this.state, nowMs, this.getWorkdays());
    const untilDue = nextDueAt === null ? MAX_SCHEDULER_DELAY_MS : Math.max(0, nextDueAt - nowMs);
    const delay = Math.max(MIN_SCHEDULER_DELAY_MS, Math.min(MAX_SCHEDULER_DELAY_MS, untilDue));
    this.timerHandle = this.setTimeout(() => {
      this.timerHandle = null;
      this.reconcile();
    }, delay);
  }

  reconcile() {
    const result = reconcileClockState(
      this.state,
      this.now(),
      this.getWorkdays(),
      {
        catchUpMs: this.catchUpMs,
        makeId: () => this.makeId(),
      },
    );
    this.state = this.store.save(result.state);
    this.onChange(this.getState(), { reason: 'reconcile' });
    if (result.events.due.length) this.onDue(result.events.due.map((entry) => ({ ...entry })));
    if (result.events.missed.length) this.onMissed(result.events.missed.map((entry) => ({ ...entry })));
    this.arm();
    return result.events;
  }

  refreshAfterWake() {
    return this.reconcile();
  }

  createAlarm(input) {
    const nowMs = this.now();
    if (this.state.alarms.length >= 50) throw new Error('最多只能保存 50 个闹钟');
    const alarm = createAlarm(input, this.makeId(), nowMs);
    if (alarm.mode === 'once') {
      const [year, month, day] = alarm.date.split('-').map(Number);
      const [hours, minutes] = alarm.time.split(':').map(Number);
      const dueAtMs = new Date(year, month - 1, day, hours, minutes, 0, 0).getTime();
      if (dueAtMs <= nowMs) throw new Error('一次性闹钟必须设在未来');
    }
    return this.persist({
      ...this.state,
      alarms: [...this.state.alarms, alarm],
    }, { reason: 'alarm-created', alarmId: alarm.id });
  }

  updateAlarm(id, patch) {
    const index = this.state.alarms.findIndex((alarm) => alarm.id === id);
    if (index < 0) throw new Error('找不到这个闹钟');
    const current = this.state.alarms[index];
    const nextAlarm = validateAlarm({
      ...current,
      ...patch,
      id: current.id,
      createdAtMs: current.createdAtMs,
      lastOccurrenceKey: null,
    });
    const alarms = [...this.state.alarms];
    alarms[index] = nextAlarm;
    return this.persist({ ...this.state, alarms }, { reason: 'alarm-updated', alarmId: id });
  }

  deleteAlarm(id) {
    if (!this.state.alarms.some((alarm) => alarm.id === id)) throw new Error('找不到这个闹钟');
    return this.persist({
      ...this.state,
      alarms: this.state.alarms.filter((alarm) => alarm.id !== id),
      alerts: this.state.alerts.filter((alert) => alert.sourceId !== id),
    }, { reason: 'alarm-deleted', alarmId: id });
  }

  startTimer(input) {
    if (this.state.timer) throw new Error('已经有一个计时器在运行');
    const timer = createTimer(input, this.makeId(), this.now());
    return this.persist({ ...this.state, timer }, { reason: 'timer-started', timerId: timer.id });
  }

  pauseTimer() {
    const timer = this.state.timer;
    if (!timer || timer.state !== 'running') throw new Error('没有正在运行的计时器');
    const remainingMs = Math.max(0, timer.dueAtMs - this.now());
    return this.persist({
      ...this.state,
      timer: { ...timer, state: 'paused', dueAtMs: null, remainingMs },
    }, { reason: 'timer-paused', timerId: timer.id });
  }

  resumeTimer() {
    const timer = this.state.timer;
    if (!timer || timer.state !== 'paused') throw new Error('没有暂停中的计时器');
    return this.persist({
      ...this.state,
      timer: {
        ...timer,
        state: 'running',
        dueAtMs: this.now() + timer.remainingMs,
        remainingMs: null,
      },
    }, { reason: 'timer-resumed', timerId: timer.id });
  }

  extendTimer(minutes = 5) {
    const timer = this.state.timer;
    if (!timer) throw new Error('没有活动计时器');
    if (!Number.isInteger(minutes) || minutes < 1 || minutes > 60) throw new Error('增加时间必须在 1 到 60 分钟之间');
    const extraMs = minutes * 60 * 1000;
    const nextTimer = timer.state === 'running'
      ? { ...timer, durationMs: timer.durationMs + extraMs, dueAtMs: timer.dueAtMs + extraMs }
      : { ...timer, durationMs: timer.durationMs + extraMs, remainingMs: timer.remainingMs + extraMs };
    return this.persist({ ...this.state, timer: nextTimer }, {
      reason: 'timer-extended',
      timerId: timer.id,
      minutes,
    });
  }

  cancelTimer() {
    const timer = this.state.timer;
    if (!timer) throw new Error('没有活动计时器');
    return this.persist({ ...this.state, timer: null }, { reason: 'timer-cancelled', timerId: timer.id });
  }

  snoozeAlert(id, minutes = this.state.preferences.defaultSnoozeMinutes) {
    if (!Number.isInteger(minutes) || minutes < 1 || minutes > 30) throw new Error('稍后提醒必须在 1 到 30 分钟之间');
    const index = this.state.alerts.findIndex((alert) => alert.id === id);
    if (index < 0) throw new Error('找不到这个提醒');
    const alerts = [...this.state.alerts];
    alerts[index] = {
      ...alerts[index],
      state: 'snoozed',
      dueAtMs: this.now() + minutes * 60 * 1000,
      ringStartedAtMs: null,
    };
    return this.persist({ ...this.state, alerts }, { reason: 'alert-snoozed', alertId: id, minutes });
  }

  dismissAlert(id) {
    if (!this.state.alerts.some((alert) => alert.id === id)) throw new Error('找不到这个提醒');
    return this.persist({
      ...this.state,
      alerts: this.state.alerts.filter((alert) => alert.id !== id),
    }, { reason: 'alert-dismissed', alertId: id });
  }

  updatePreferences(preferences) {
    const nextPreferences = validatePreferences({ ...this.state.preferences, ...preferences });
    return this.persist({ ...this.state, preferences: nextPreferences }, { reason: 'preferences-updated' });
  }
}

module.exports = {
  ClockService,
  MAX_SCHEDULER_DELAY_MS,
  MIN_SCHEDULER_DELAY_MS,
};
