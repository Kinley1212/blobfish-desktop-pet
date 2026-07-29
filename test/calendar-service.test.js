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

test('refresh after wake immediately reloads events and catches a recently started meeting', async () => {
  const emitted = [];
  const wakeTime = new Date('2026-07-15T10:03:00Z');
  const meeting = {
    id: 'wake-meeting',
    title: '醒来后的会议',
    start: new Date('2026-07-15T10:00:00Z'),
    end: new Date('2026-07-15T10:30:00Z'),
    allDay: false,
  };
  let reads = 0;
  const service = new CalendarService({
    helperPath: '/unused',
    onEvent: (event) => emitted.push(event),
    now: () => wakeTime,
    read: async () => {
      reads += 1;
      return { status: 'authorized', events: [meeting] };
    },
    setInterval: () => 1,
    clearInterval: () => {},
  });

  service.enabled = true;
  await service.refreshAfterWake(
    wakeTime,
    new Date('2026-07-15T09:55:00Z'),
  );

  assert.equal(reads, 1);
  assert.deepEqual(emitted.map((event) => event.type), ['starting']);
  assert.equal(emitted[0].event.id, 'wake-meeting');
});

test('refresh after wake trusts the refreshed result instead of stale cached events', async () => {
  const emitted = [];
  const wakeTime = new Date('2026-07-15T10:03:00Z');
  const service = new CalendarService({
    helperPath: '/unused',
    onEvent: (event) => emitted.push(event),
    now: () => wakeTime,
    read: async () => ({ status: 'authorized', events: [] }),
    setInterval: () => 1,
    clearInterval: () => {},
  });
  service.enabled = true;
  service.events = [{
    id: 'cancelled-during-sleep',
    title: '睡眠期间已取消',
    start: new Date('2026-07-15T10:00:00Z'),
    end: new Date('2026-07-15T10:30:00Z'),
    allDay: false,
  }];

  await service.refreshAfterWake(
    wakeTime,
    new Date('2026-07-15T09:55:00Z'),
  );

  assert.deepEqual(service.events, []);
  assert.deepEqual(emitted, []);
});

test('refresh after wake replaces an in-flight poll without adding timers or accepting its stale result', async () => {
  const emitted = [];
  const wakeTime = new Date('2026-07-15T10:03:00Z');
  const freshMeeting = {
    id: 'fresh-meeting',
    title: '最新会议',
    start: new Date('2026-07-15T10:01:00Z'),
    end: new Date('2026-07-15T10:30:00Z'),
    allDay: false,
  };
  const staleMeeting = {
    id: 'stale-meeting',
    title: '旧读取结果',
    start: new Date('2026-07-15T10:02:00Z'),
    end: new Date('2026-07-15T10:30:00Z'),
    allDay: false,
  };
  let reads = 0;
  let resolveStaleRead;
  let staleSignal;
  let intervalCalls = 0;
  const service = new CalendarService({
    helperPath: '/unused',
    onEvent: (event) => emitted.push(event),
    now: () => wakeTime,
    read: ({ signal }) => {
      reads += 1;
      if (reads === 1) {
        staleSignal = signal;
        return new Promise((resolve) => {
          resolveStaleRead = resolve;
        });
      }
      return Promise.resolve({ status: 'authorized', events: [freshMeeting] });
    },
    setInterval: () => {
      intervalCalls += 1;
      return intervalCalls;
    },
    clearInterval: () => {},
  });

  service.setEnabled(true);
  assert.equal(intervalCalls, 2);
  await service.refreshAfterWake(
    wakeTime,
    new Date('2026-07-15T09:55:00Z'),
  );

  assert.equal(intervalCalls, 2);
  assert.equal(staleSignal.aborted, true);
  assert.deepEqual(service.events.map((event) => event.id), ['fresh-meeting']);
  assert.deepEqual(emitted.map((event) => event.event.id), ['fresh-meeting']);

  resolveStaleRead({ status: 'authorized', events: [staleMeeting] });
  await new Promise((resolve) => setImmediate(resolve));

  assert.deepEqual(service.events.map((event) => event.id), ['fresh-meeting']);
  assert.deepEqual(emitted.map((event) => event.event.id), ['fresh-meeting']);
});

test('wake catch-up is bounded and does not replay an old meeting', async () => {
  const emitted = [];
  const wakeTime = new Date('2026-07-15T10:03:00Z');
  const service = new CalendarService({
    helperPath: '/unused',
    onEvent: (event) => emitted.push(event),
    now: () => wakeTime,
    read: async () => ({
      status: 'authorized',
      events: [{
        id: 'old-meeting',
        title: '很早以前的会议',
        start: new Date('2026-07-15T09:50:00Z'),
        end: new Date('2026-07-15T10:30:00Z'),
        allDay: false,
      }],
    }),
    setInterval: () => 1,
    clearInterval: () => {},
  });

  service.enabled = true;
  await service.refreshAfterWake(
    wakeTime,
    new Date('2026-07-15T09:00:00Z'),
  );

  assert.deepEqual(emitted, []);
});

test('normal evaluation keeps the short starting grace when no wake catch-up is pending', () => {
  const emitted = [];
  const now = new Date('2026-07-15T10:03:00Z');
  const service = new CalendarService({
    helperPath: '/unused',
    onEvent: (event) => emitted.push(event),
  });
  service.events = [{
    id: 'ordinary-old-meeting',
    title: '普通轮询不补发',
    start: new Date('2026-07-15T10:01:00Z'),
    end: new Date('2026-07-15T10:30:00Z'),
    allDay: false,
  }];

  service.evaluate(now, { startingSinceMs: null });

  assert.deepEqual(emitted, []);
});

test('calendar notification deduplication is bounded for a long-running pet', () => {
  const service = new CalendarService({
    helperPath: '/unused',
    onEvent: () => {},
    maxNotifiedEntries: 32,
  });
  const now = new Date('2026-07-15T09:00:00Z');

  for (let index = 0; index < 80; index += 1) {
    service.events = [{
      id: `meeting-${index}`,
      title: `会议 ${index}`,
      start: new Date(now.getTime() + 5 * 60 * 1000),
      end: new Date(now.getTime() + 35 * 60 * 1000),
      allDay: false,
    }];
    service.evaluate(now);
  }

  assert.equal(service.notified.size, 32);
});

test('a successful poll leaves the notification cache bounded', async () => {
  const now = new Date('2026-07-15T09:00:00Z');
  const events = Array.from({ length: 80 }, (_, index) => ({
    id: `poll-meeting-${index}`,
    title: `轮询会议 ${index}`,
    start: new Date(now.getTime() + 5 * 60 * 1000),
    end: new Date(now.getTime() + 35 * 60 * 1000),
    allDay: false,
  }));
  const service = new CalendarService({
    helperPath: '/unused',
    onEvent: () => {},
    now: () => now,
    maxNotifiedEntries: 32,
    read: async () => ({ status: 'authorized', events }),
  });
  service.enabled = true;

  await service.poll();

  assert.equal(service.notified.size, 32);
});
