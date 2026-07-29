const {
  DEFAULT_NEEDS_INPUT_SOUND_ID,
  DEFAULT_TASK_COMPLETE_SOUND_ID,
  isValidTaskCompleteSoundId,
} = require('./sound-catalog');

const CLOCK_STATE_VERSION = 1;
const TIME_PATTERN = /^(?:[01]\d|2[0-3]):[0-5]\d$/;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const MAX_LABEL_LENGTH = 60;
const MAX_ALARMS = 50;
const MIN_TIMER_MS = 60 * 1000;
const MAX_TIMER_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_SNOOZE_MINUTES = 30;
const DEFAULT_CATCH_UP_MS = 10 * 60 * 1000;
const MAX_RECONCILE_LOOKBACK_MS = 8 * 24 * 60 * 60 * 1000;
const DEFAULT_CLOCK_STATE = Object.freeze({
  version: CLOCK_STATE_VERSION,
  preferences: Object.freeze({
    alarmSound: Object.freeze({ enabled: true, soundId: DEFAULT_NEEDS_INPUT_SOUND_ID }),
    timerSound: Object.freeze({ enabled: true, soundId: DEFAULT_TASK_COMPLETE_SOUND_ID }),
    allowSoundDuringQuietHours: true,
    defaultSnoozeMinutes: 5,
  }),
  alarms: Object.freeze([]),
  timer: null,
  alerts: Object.freeze([]),
  lastReconciledAtMs: 0,
});

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function requireSafeTimestamp(value, label, options = {}) {
  const { allowNull = false } = options;
  if (allowNull && value === null) return null;
  if (!Number.isSafeInteger(value) || value < 0) throw new Error(`${label} must be a non-negative timestamp`);
  return value;
}

function requireBoolean(value, label) {
  if (typeof value !== 'boolean') throw new Error(`${label} must be a boolean`);
  return value;
}

function requireId(value, label) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(value)) {
    throw new Error(`${label} is invalid`);
  }
  return value;
}

function normalizeLabel(value, label = 'label') {
  if (value === undefined || value === null) return '';
  if (typeof value !== 'string') throw new Error(`${label} must be a string`);
  const normalized = value.replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim();
  if (normalized.length > MAX_LABEL_LENGTH) throw new Error(`${label} must be at most ${MAX_LABEL_LENGTH} characters`);
  return normalized;
}

function isValidLocalDate(value) {
  if (typeof value !== 'string' || !DATE_PATTERN.test(value)) return false;
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(year, month - 1, day);
  return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day;
}

function requireLocalDate(value, label) {
  if (!isValidLocalDate(value)) throw new Error(`${label} must use YYYY-MM-DD`);
  return value;
}

function requireLocalTime(value, label) {
  if (typeof value !== 'string' || !TIME_PATTERN.test(value)) throw new Error(`${label} must use HH:MM`);
  return value;
}

function normalizeWeekdays(value, label, options = {}) {
  const { allowEmpty = false } = options;
  if (!Array.isArray(value) || value.length > 7) throw new Error(`${label} must be an array`);
  const weekdays = [...new Set(value)];
  if (weekdays.some((day) => !Number.isInteger(day) || day < 0 || day > 6)) {
    throw new Error(`${label} entries must be integers from 0 to 6`);
  }
  if (!allowEmpty && weekdays.length === 0) throw new Error(`${label} cannot be empty`);
  return weekdays.sort((a, b) => a - b);
}

function normalizeSoundSetting(value, fallback, label) {
  if (!isPlainObject(value)) throw new Error(`${label} must be an object`);
  return {
    enabled: requireBoolean(value.enabled, `${label}.enabled`),
    soundId: isValidTaskCompleteSoundId(value.soundId) ? value.soundId : fallback.soundId,
  };
}

function validatePreferences(value) {
  if (!isPlainObject(value)) throw new Error('preferences must be an object');
  const snooze = value.defaultSnoozeMinutes;
  if (!Number.isInteger(snooze) || snooze < 1 || snooze > MAX_SNOOZE_MINUTES) {
    throw new Error(`preferences.defaultSnoozeMinutes must be between 1 and ${MAX_SNOOZE_MINUTES}`);
  }
  return {
    alarmSound: normalizeSoundSetting(
      value.alarmSound,
      DEFAULT_CLOCK_STATE.preferences.alarmSound,
      'preferences.alarmSound',
    ),
    timerSound: normalizeSoundSetting(
      value.timerSound,
      DEFAULT_CLOCK_STATE.preferences.timerSound,
      'preferences.timerSound',
    ),
    allowSoundDuringQuietHours: requireBoolean(
      value.allowSoundDuringQuietHours,
      'preferences.allowSoundDuringQuietHours',
    ),
    defaultSnoozeMinutes: snooze,
  };
}

function validateAlarm(value, label = 'alarm') {
  if (!isPlainObject(value)) throw new Error(`${label} must be an object`);
  const modes = new Set(['once', 'daily', 'workdays', 'weekly']);
  if (!modes.has(value.mode)) throw new Error(`${label}.mode is invalid`);
  const date = value.mode === 'once' ? requireLocalDate(value.date, `${label}.date`) : null;
  const weekdays = value.mode === 'weekly'
    ? normalizeWeekdays(value.weekdays, `${label}.weekdays`)
    : [];
  const lastOccurrenceKey = value.lastOccurrenceKey === null
    ? null
    : requireId(value.lastOccurrenceKey, `${label}.lastOccurrenceKey`);
  return {
    id: requireId(value.id, `${label}.id`),
    label: normalizeLabel(value.label, `${label}.label`),
    enabled: requireBoolean(value.enabled, `${label}.enabled`),
    mode: value.mode,
    time: requireLocalTime(value.time, `${label}.time`),
    date,
    weekdays,
    lastOccurrenceKey,
    createdAtMs: requireSafeTimestamp(value.createdAtMs, `${label}.createdAtMs`),
  };
}

function validateTimer(value, label = 'timer') {
  if (value === null) return null;
  if (!isPlainObject(value)) throw new Error(`${label} must be an object`);
  if (!['running', 'paused'].includes(value.state)) throw new Error(`${label}.state is invalid`);
  if (!Number.isSafeInteger(value.durationMs) || value.durationMs < MIN_TIMER_MS || value.durationMs > MAX_TIMER_MS) {
    throw new Error(`${label}.durationMs is out of range`);
  }
  const dueAtMs = requireSafeTimestamp(value.dueAtMs, `${label}.dueAtMs`, { allowNull: true });
  const remainingMs = value.remainingMs === null
    ? null
    : requireSafeTimestamp(value.remainingMs, `${label}.remainingMs`);
  if (value.state === 'running' && dueAtMs === null) throw new Error(`${label}.dueAtMs is required while running`);
  if (value.state === 'paused' && remainingMs === null) throw new Error(`${label}.remainingMs is required while paused`);
  return {
    id: requireId(value.id, `${label}.id`),
    label: normalizeLabel(value.label, `${label}.label`),
    durationMs: value.durationMs,
    state: value.state,
    createdAtMs: requireSafeTimestamp(value.createdAtMs, `${label}.createdAtMs`),
    dueAtMs: value.state === 'running' ? dueAtMs : null,
    remainingMs: value.state === 'paused' ? Math.min(remainingMs, MAX_TIMER_MS) : null,
  };
}

function validateAlert(value, label = 'alert') {
  if (!isPlainObject(value)) throw new Error(`${label} must be an object`);
  if (!['alarm', 'timer'].includes(value.sourceType)) throw new Error(`${label}.sourceType is invalid`);
  if (!['ringing', 'snoozed'].includes(value.state)) throw new Error(`${label}.state is invalid`);
  return {
    id: requireId(value.id, `${label}.id`),
    sourceType: value.sourceType,
    sourceId: requireId(value.sourceId, `${label}.sourceId`),
    label: normalizeLabel(value.label, `${label}.label`),
    originalDueAtMs: requireSafeTimestamp(value.originalDueAtMs, `${label}.originalDueAtMs`),
    dueAtMs: requireSafeTimestamp(value.dueAtMs, `${label}.dueAtMs`),
    state: value.state,
    ringStartedAtMs: requireSafeTimestamp(value.ringStartedAtMs, `${label}.ringStartedAtMs`, { allowNull: true }),
  };
}

function validateClockState(value) {
  if (!isPlainObject(value)) throw new Error('clock state must be an object');
  if (value.version !== CLOCK_STATE_VERSION) throw new Error('unsupported clock state version');
  if (!Array.isArray(value.alarms) || value.alarms.length > MAX_ALARMS) {
    throw new Error(`alarms must contain at most ${MAX_ALARMS} entries`);
  }
  if (!Array.isArray(value.alerts) || value.alerts.length > MAX_ALARMS + 1) {
    throw new Error('alerts has too many entries');
  }
  const alarms = value.alarms.map((alarm, index) => validateAlarm(alarm, `alarms[${index}]`));
  const alerts = value.alerts.map((alert, index) => validateAlert(alert, `alerts[${index}]`));
  const ids = new Set();
  for (const entry of [...alarms, ...alerts]) {
    if (ids.has(entry.id)) throw new Error(`duplicate clock id: ${entry.id}`);
    ids.add(entry.id);
  }
  const timer = validateTimer(value.timer);
  if (timer && ids.has(timer.id)) throw new Error(`duplicate clock id: ${timer.id}`);
  return {
    version: CLOCK_STATE_VERSION,
    preferences: validatePreferences(value.preferences),
    alarms,
    timer,
    alerts,
    lastReconciledAtMs: requireSafeTimestamp(value.lastReconciledAtMs, 'lastReconciledAtMs'),
  };
}

function pad(value) {
  return String(value).padStart(2, '0');
}

function localDateKey(date) {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function occurrenceKey(alarm, date) {
  return `${alarm.id}:${localDateKey(date)}:${alarm.time.replace(':', '')}`;
}

function weekdaysForAlarm(alarm, workdays) {
  if (alarm.mode === 'daily') return [0, 1, 2, 3, 4, 5, 6];
  if (alarm.mode === 'workdays') return normalizeWeekdays(workdays, 'workdays');
  if (alarm.mode === 'weekly') return alarm.weekdays;
  return [];
}

function alarmOccurrenceOnDate(alarm, date, workdays) {
  const dateKey = localDateKey(date);
  if (alarm.mode === 'once') {
    if (alarm.date !== dateKey) return null;
  } else if (!weekdaysForAlarm(alarm, workdays).includes(date.getDay())) {
    return null;
  }
  const [hours, minutes] = alarm.time.split(':').map(Number);
  const occurrence = new Date(date.getFullYear(), date.getMonth(), date.getDate(), hours, minutes, 0, 0);
  return {
    dueAtMs: occurrence.getTime(),
    key: occurrenceKey(alarm, date),
  };
}

function collectAlarmOccurrences(alarm, startExclusiveMs, endInclusiveMs, workdays) {
  if (!alarm.enabled || endInclusiveMs <= startExclusiveMs) return [];
  const startDate = new Date(startExclusiveMs);
  startDate.setHours(0, 0, 0, 0);
  const endDate = new Date(endInclusiveMs);
  endDate.setHours(0, 0, 0, 0);
  const occurrences = [];
  for (let cursor = new Date(startDate); cursor <= endDate; cursor.setDate(cursor.getDate() + 1)) {
    const occurrence = alarmOccurrenceOnDate(alarm, cursor, workdays);
    if (
      occurrence
      && occurrence.dueAtMs > startExclusiveMs
      && occurrence.dueAtMs <= endInclusiveMs
      && occurrence.key !== alarm.lastOccurrenceKey
    ) {
      occurrences.push(occurrence);
    }
  }
  return occurrences;
}

function getNextAlarmOccurrence(alarm, afterMs, workdays) {
  if (!alarm.enabled) return null;
  const start = new Date(afterMs);
  start.setHours(0, 0, 0, 0);
  const daysToCheck = alarm.mode === 'once' ? 370 : 8;
  for (let dayOffset = 0; dayOffset < daysToCheck; dayOffset += 1) {
    const cursor = new Date(start);
    cursor.setDate(cursor.getDate() + dayOffset);
    const occurrence = alarmOccurrenceOnDate(alarm, cursor, workdays);
    if (occurrence && occurrence.dueAtMs > afterMs && occurrence.key !== alarm.lastOccurrenceKey) {
      return occurrence;
    }
  }
  return null;
}

function createAlert({ id, sourceType, sourceId, label, dueAtMs, nowMs }) {
  return {
    id,
    sourceType,
    sourceId,
    label,
    originalDueAtMs: dueAtMs,
    dueAtMs,
    state: 'ringing',
    ringStartedAtMs: nowMs,
  };
}

function reconcileClockState(inputState, nowMs, workdays, options = {}) {
  const state = validateClockState(inputState);
  requireSafeTimestamp(nowMs, 'nowMs');
  const catchUpMs = Number.isSafeInteger(options.catchUpMs)
    ? Math.max(0, options.catchUpMs)
    : DEFAULT_CATCH_UP_MS;
  const makeId = typeof options.makeId === 'function'
    ? options.makeId
    : (sourceId, key) => `alert:${sourceId}:${key.replace(/[^A-Za-z0-9._:-]/g, '-')}`;
  const events = { due: [], missed: [] };

  if (state.timer && state.timer.state === 'running' && state.timer.dueAtMs <= nowMs) {
    const timer = state.timer;
    const alert = createAlert({
      id: makeId(timer.id, String(timer.dueAtMs)),
      sourceType: 'timer',
      sourceId: timer.id,
      label: timer.label,
      dueAtMs: timer.dueAtMs,
      nowMs,
    });
    state.timer = null;
    if (nowMs - alert.originalDueAtMs <= catchUpMs) {
      state.alerts.push(alert);
      events.due.push(clone(alert));
    } else {
      events.missed.push({
        sourceType: 'timer',
        sourceId: timer.id,
        label: timer.label,
        dueAtMs: timer.dueAtMs,
      });
    }
  }

  for (const alert of state.alerts) {
    if (alert.state !== 'snoozed' || alert.dueAtMs > nowMs) continue;
    alert.state = 'ringing';
    alert.ringStartedAtMs = nowMs;
    events.due.push(clone(alert));
  }

  const previousCheck = state.lastReconciledAtMs;
  const startExclusiveMs = previousCheck > nowMs
    ? nowMs - 1000
    : Math.max(previousCheck, nowMs - MAX_RECONCILE_LOOKBACK_MS);
  for (const alarm of state.alarms) {
    const occurrences = collectAlarmOccurrences(alarm, startExclusiveMs, nowMs, workdays);
    if (occurrences.length === 0) continue;
    const occurrence = occurrences[occurrences.length - 1];
    alarm.lastOccurrenceKey = occurrence.key;
    if (alarm.mode === 'once') alarm.enabled = false;
    if (nowMs - occurrence.dueAtMs <= catchUpMs) {
      const alert = createAlert({
        id: makeId(alarm.id, occurrence.key),
        sourceType: 'alarm',
        sourceId: alarm.id,
        label: alarm.label,
        dueAtMs: occurrence.dueAtMs,
        nowMs,
      });
      if (!state.alerts.some((candidate) => candidate.id === alert.id)) {
        state.alerts.push(alert);
        events.due.push(clone(alert));
      }
    } else {
      events.missed.push({
        sourceType: 'alarm',
        sourceId: alarm.id,
        label: alarm.label,
        dueAtMs: occurrence.dueAtMs,
      });
    }
  }

  state.lastReconciledAtMs = nowMs;
  return { state: validateClockState(state), events };
}

function getNextDueAt(inputState, nowMs, workdays) {
  const state = validateClockState(inputState);
  const candidates = [];
  if (state.timer?.state === 'running') candidates.push(state.timer.dueAtMs);
  for (const alert of state.alerts) {
    if (alert.state === 'snoozed') candidates.push(alert.dueAtMs);
  }
  for (const alarm of state.alarms) {
    const occurrence = getNextAlarmOccurrence(alarm, nowMs, workdays);
    if (occurrence) candidates.push(occurrence.dueAtMs);
  }
  return candidates.length ? Math.min(...candidates) : null;
}

function createAlarm(input, id, nowMs) {
  if (!isPlainObject(input)) throw new Error('alarm input must be an object');
  return validateAlarm({
    id,
    label: input.label || '',
    enabled: input.enabled === undefined ? true : input.enabled,
    mode: input.mode,
    time: input.time,
    date: input.mode === 'once' ? input.date : null,
    weekdays: input.mode === 'weekly' ? input.weekdays : [],
    lastOccurrenceKey: null,
    createdAtMs: nowMs,
  });
}

function createTimer(input, id, nowMs) {
  if (!isPlainObject(input)) throw new Error('timer input must be an object');
  const durationMinutes = Number(input.durationMinutes);
  const durationMs = durationMinutes * 60 * 1000;
  return validateTimer({
    id,
    label: input.label || '',
    durationMs,
    state: 'running',
    createdAtMs: nowMs,
    dueAtMs: nowMs + durationMs,
    remainingMs: null,
  });
}

module.exports = {
  CLOCK_STATE_VERSION,
  DEFAULT_CATCH_UP_MS,
  DEFAULT_CLOCK_STATE,
  MAX_ALARMS,
  MAX_LABEL_LENGTH,
  MAX_SNOOZE_MINUTES,
  MAX_TIMER_MS,
  MIN_TIMER_MS,
  alarmOccurrenceOnDate,
  collectAlarmOccurrences,
  createAlarm,
  createTimer,
  getNextAlarmOccurrence,
  getNextDueAt,
  isValidLocalDate,
  localDateKey,
  normalizeLabel,
  reconcileClockState,
  validateAlarm,
  validateClockState,
  validatePreferences,
  validateTimer,
};
