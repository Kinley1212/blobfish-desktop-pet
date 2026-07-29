const test = require('node:test');
const assert = require('node:assert/strict');
const { ClockService } = require('../src/core/clock-service');
const { DEFAULT_CLOCK_STATE, validateClockState } = require('../src/core/clock-engine');

function memoryStore() {
  let state = validateClockState(JSON.parse(JSON.stringify(DEFAULT_CLOCK_STATE)));
  return {
    load: () => JSON.parse(JSON.stringify(state)),
    get: () => JSON.parse(JSON.stringify(state)),
    save: (next) => {
      state = validateClockState(next);
      return JSON.parse(JSON.stringify(state));
    },
  };
}

function serviceFixture(nowMs) {
  let current = nowMs;
  let nextId = 0;
  const due = [];
  const missed = [];
  const service = new ClockService(memoryStore(), {
    now: () => current,
    makeId: () => `clock-${++nextId}`,
    setTimeout: () => 1,
    clearTimeout: () => {},
    onDue: (items) => due.push(...items),
    onMissed: (items) => missed.push(...items),
  });
  return {
    service,
    due,
    missed,
    setNow: (value) => { current = value; },
  };
}

test('clock service supports one active timer with pause, resume and extension', () => {
  const start = new Date(2026, 6, 29, 10, 0).getTime();
  const fixture = serviceFixture(start);
  fixture.service.start();
  fixture.service.startTimer({ durationMinutes: 25, label: '专注' });
  assert.throws(() => fixture.service.startTimer({ durationMinutes: 5 }), /已经有一个计时器/);

  fixture.setNow(start + 5 * 60 * 1000);
  fixture.service.pauseTimer();
  assert.equal(fixture.service.getState().timer.remainingMs, 20 * 60 * 1000);
  fixture.service.extendTimer(5);
  assert.equal(fixture.service.getState().timer.remainingMs, 25 * 60 * 1000);
  fixture.service.resumeTimer();
  assert.equal(fixture.service.getState().timer.dueAtMs, start + 30 * 60 * 1000);
});

test('clock service emits due timer after reconciliation and can dismiss it', () => {
  const start = new Date(2026, 6, 29, 10, 0).getTime();
  const fixture = serviceFixture(start);
  fixture.service.start();
  fixture.service.startTimer({ durationMinutes: 1, label: '茶' });
  fixture.setNow(start + 60 * 1000);
  fixture.service.reconcile();
  assert.equal(fixture.due.length, 1);
  assert.equal(fixture.service.getState().alerts.length, 1);
  fixture.service.dismissAlert(fixture.due[0].id);
  assert.equal(fixture.service.getState().alerts.length, 0);
});

test('clock service snoozes alerts idempotently through a new due time', () => {
  const start = new Date(2026, 6, 29, 10, 0).getTime();
  const fixture = serviceFixture(start);
  fixture.service.start();
  fixture.service.startTimer({ durationMinutes: 1 });
  fixture.setNow(start + 60 * 1000);
  fixture.service.reconcile();
  const alertId = fixture.due[0].id;
  fixture.service.snoozeAlert(alertId, 5);
  assert.equal(fixture.service.getState().alerts[0].state, 'snoozed');
  fixture.setNow(start + 6 * 60 * 1000);
  fixture.service.reconcile();
  assert.equal(fixture.service.getState().alerts[0].state, 'ringing');
  assert.equal(fixture.due.length, 2);
});
