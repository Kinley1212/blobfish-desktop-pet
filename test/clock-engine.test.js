const test = require('node:test');
const assert = require('node:assert/strict');
const {
  DEFAULT_CLOCK_STATE,
  alarmOccurrenceOnDate,
  collectAlarmOccurrences,
  createAlarm,
  createTimer,
  getNextAlarmOccurrence,
  getNextDueAt,
  reconcileClockState,
  validateClockState,
} = require('../src/core/clock-engine');

function state(overrides = {}) {
  return validateClockState({
    ...JSON.parse(JSON.stringify(DEFAULT_CLOCK_STATE)),
    ...overrides,
  });
}

test('clock state validates an empty default state', () => {
  assert.deepEqual(validateClockState(JSON.parse(JSON.stringify(DEFAULT_CLOCK_STATE))), DEFAULT_CLOCK_STATE);
});

test('alarm occurrence respects workdays and local time', () => {
  const alarm = createAlarm({
    mode: 'workdays',
    time: '07:30',
    label: '起床',
  }, 'alarm-1', 1);
  const monday = new Date(2026, 6, 27, 6, 0);
  const sunday = new Date(2026, 6, 26, 6, 0);
  assert.equal(alarmOccurrenceOnDate(alarm, sunday, [1, 2, 3, 4, 5]), null);
  assert.equal(
    alarmOccurrenceOnDate(alarm, monday, [1, 2, 3, 4, 5]).dueAtMs,
    new Date(2026, 6, 27, 7, 30).getTime(),
  );
});

test('weekly alarm returns the next matching occurrence', () => {
  const alarm = createAlarm({
    mode: 'weekly',
    time: '18:15',
    weekdays: [2, 4],
  }, 'alarm-2', 1);
  const now = new Date(2026, 6, 27, 20, 0).getTime();
  const occurrence = getNextAlarmOccurrence(alarm, now, [1, 2, 3, 4, 5]);
  assert.equal(occurrence.dueAtMs, new Date(2026, 6, 28, 18, 15).getTime());
});

test('collect alarm occurrences excludes a delivered local occurrence', () => {
  const alarm = {
    ...createAlarm({ mode: 'daily', time: '09:00' }, 'alarm-3', 1),
    lastOccurrenceKey: 'alarm-3:2026-07-29:0900',
  };
  const occurrences = collectAlarmOccurrences(
    alarm,
    new Date(2026, 6, 28, 23, 0).getTime(),
    new Date(2026, 6, 29, 10, 0).getTime(),
    [1, 2, 3, 4, 5],
  );
  assert.deepEqual(occurrences, []);
});

test('running timer becomes a ringing alert exactly once', () => {
  const now = new Date(2026, 6, 29, 10, 0).getTime();
  const timer = createTimer({ durationMinutes: 5, label: '泡茶' }, 'timer-1', now);
  const input = state({ timer, lastReconciledAtMs: now });
  const first = reconcileClockState(input, now + 5 * 60 * 1000, [1, 2, 3, 4, 5], {
    makeId: () => 'alert-1',
  });
  assert.equal(first.state.timer, null);
  assert.equal(first.state.alerts.length, 1);
  assert.equal(first.events.due.length, 1);

  const second = reconcileClockState(first.state, now + 5 * 60 * 1000 + 1000, [1, 2, 3, 4, 5], {
    makeId: () => 'alert-2',
  });
  assert.equal(second.events.due.length, 0);
  assert.equal(second.state.alerts.length, 1);
});

test('old timer is reported as missed instead of ringing late', () => {
  const start = new Date(2026, 6, 29, 10, 0).getTime();
  const timer = createTimer({ durationMinutes: 1 }, 'timer-old', start);
  const result = reconcileClockState(
    state({ timer, lastReconciledAtMs: start }),
    start + 20 * 60 * 1000,
    [1, 2, 3, 4, 5],
    { makeId: () => 'unused' },
  );
  assert.equal(result.state.alerts.length, 0);
  assert.equal(result.events.missed.length, 1);
});

test('one-time alarm disables itself after firing', () => {
  const due = new Date(2026, 6, 29, 10, 30).getTime();
  const alarm = createAlarm({
    mode: 'once',
    date: '2026-07-29',
    time: '10:30',
    label: '开会',
  }, 'alarm-once', due - 1000);
  const result = reconcileClockState(
    state({ alarms: [alarm], lastReconciledAtMs: due - 60 * 1000 }),
    due,
    [1, 2, 3, 4, 5],
    { makeId: () => 'alert-once' },
  );
  assert.equal(result.state.alarms[0].enabled, false);
  assert.equal(result.events.due[0].label, '开会');
});

test('next due considers timer, snoozed alert and alarms', () => {
  const now = new Date(2026, 6, 29, 10, 0).getTime();
  const timer = createTimer({ durationMinutes: 25 }, 'timer-next', now);
  const clock = state({
    timer,
    alarms: [createAlarm({ mode: 'daily', time: '11:00' }, 'alarm-next', now)],
    alerts: [{
      id: 'alert-next',
      sourceType: 'alarm',
      sourceId: 'alarm-next',
      label: '',
      originalDueAtMs: now - 1000,
      dueAtMs: now + 5 * 60 * 1000,
      state: 'snoozed',
      ringStartedAtMs: null,
    }],
    lastReconciledAtMs: now,
  });
  assert.equal(getNextDueAt(clock, now, [1, 2, 3, 4, 5]), now + 5 * 60 * 1000);
});

test('labels reject control characters after normalization and stay bounded', () => {
  const alarm = createAlarm({
    mode: 'daily',
    time: '08:00',
    label: '  开会\u0000提醒  ',
  }, 'alarm-label', 1);
  assert.equal(alarm.label, '开会 提醒');
  assert.throws(() => createAlarm({
    mode: 'daily',
    time: '08:00',
    label: '长'.repeat(61),
  }, 'alarm-long', 1), /at most 60/);
});
