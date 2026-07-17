const test = require('node:test');
const assert = require('node:assert/strict');
const { CalendarService, parseCalendarOutput } = require('../src/core/calendar-service');

test('validates and converts calendar helper output', () => {
  const result = parseCalendarOutput(JSON.stringify({
    status: 'authorized',
    events: [{ id: 'one', title: '设计评审', start: '2026-07-15T10:00:00Z', end: '2026-07-15T10:30:00Z', allDay: false }],
  }));
  assert.equal(result.status, 'authorized');
  assert.equal(result.events[0].start instanceof Date, true);
  assert.throws(() => parseCalendarOutput('{"status":"authorized","events":[{"id":"x"}]}'), /metadata/);
});

test('emits upcoming and starting once while ignoring all-day events', () => {
  const emitted = [];
  const now = new Date('2026-07-15T09:50:00Z');
  const service = new CalendarService({ helperPath: '/unused', onEvent: (event) => emitted.push(event), now: () => now });
  service.events = [
    { id: 'meeting', title: '评审', start: new Date('2026-07-15T10:00:00Z'), end: new Date('2026-07-15T10:30:00Z'), allDay: false },
    { id: 'all-day', title: '假期', start: new Date('2026-07-15T00:00:00Z'), end: new Date('2026-07-16T00:00:00Z'), allDay: true },
  ];

  service.evaluate(now);
  service.evaluate(now);
  service.evaluate(new Date('2026-07-15T10:00:20Z'));
  service.evaluate(new Date('2026-07-15T10:00:20Z'));
  assert.deepEqual(emitted.map((event) => event.type), ['upcoming', 'starting']);
  assert.equal(emitted[0].minutes, 10);
});

test('ignores a calendar result that finishes after the integration is disabled', async () => {
  let resolveRead;
  const statuses = [];
  const service = new CalendarService({
    helperPath: '/unused',
    onEvent: () => {},
    onStatus: (status) => statuses.push(status),
    read: () => new Promise((resolve) => { resolveRead = resolve; }),
    setInterval: () => 1,
    clearInterval: () => {},
  });

  service.setEnabled(true);
  service.setEnabled(false);
  resolveRead({ status: 'authorized', events: [] });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(service.status, 'disabled');
  assert.deepEqual(statuses, ['requesting', 'disabled']);
});
