const test = require('node:test');
const assert = require('node:assert/strict');
const {
  ReminderScheduler,
  getScheduleReminder,
  isInQuietHours,
} = require('../src/core/reminder-scheduler');

const schedule = {
  workdays: [1, 2, 3, 4, 5],
  lunchTime: '12:30',
  offWorkTime: '18:00',
  lunchReminder: true,
  offWorkReminder: true,
  halfHourReminders: true,
};

function localDate(day, hours, minutes) {
  const date = new Date(2026, 6, 13 + day, hours, minutes, 0, 0);
  return date;
}

test('schedule uses configured meal/off-work times and workdays', () => {
  assert.equal(getScheduleReminder(localDate(0, 12, 25), schedule).event, 'schedule.lunchSoon');
  assert.equal(getScheduleReminder(localDate(0, 17, 30), schedule).event, 'schedule.offWorkHalfHour');
  assert.equal(getScheduleReminder(localDate(0, 17, 55), schedule).event, 'schedule.offWorkSoon');
  assert.equal(getScheduleReminder(localDate(5, 12, 25), schedule), null);
});

test('off-work farewell follows the next configured workday instead of assuming Friday ends the week', () => {
  const friday = localDate(4, 17, 55);
  assert.equal(getScheduleReminder(friday, schedule).context.farewell, '下週見');
  assert.equal(
    getScheduleReminder(friday, { ...schedule, workdays: [1, 2, 3, 4, 5, 6] }).context.farewell,
    '明天見',
  );
});

test('catch-up polling recovers a recently crossed boundary without repeating it', () => {
  const scheduler = new ReminderScheduler();
  assert.equal(scheduler.poll(localDate(0, 12, 24), schedule), null);

  const caughtUp = scheduler.poll(localDate(0, 12, 26), schedule);
  assert.equal(caughtUp.event, 'schedule.lunchSoon');
  assert.equal(scheduler.poll(localDate(0, 12, 26), schedule), null);
  assert.equal(scheduler.poll(localDate(0, 12, 27), schedule), null);
});

test('half-hour reminders survive timer drift across the exact minute', () => {
  const scheduler = new ReminderScheduler();
  assert.equal(scheduler.poll(localDate(0, 14, 29), schedule), null);
  assert.equal(scheduler.poll(localDate(0, 14, 31), schedule).event, 'schedule.halfHour');
});

test('stale reminders are not replayed after a long sleep', () => {
  const scheduler = new ReminderScheduler();
  assert.equal(scheduler.poll(localDate(0, 12, 24), schedule), null);
  assert.equal(scheduler.poll(localDate(0, 13, 27), schedule), null);
});

test('catch-up polling respects nonstandard configured workdays', () => {
  const weekendSchedule = { ...schedule, workdays: [0, 6] };
  const scheduler = new ReminderScheduler();
  assert.equal(scheduler.poll(localDate(5, 12, 24), weekendSchedule), null);
  assert.equal(scheduler.poll(localDate(5, 12, 26), weekendSchedule).event, 'schedule.lunchSoon');

  const weekdayScheduler = new ReminderScheduler();
  assert.equal(weekdayScheduler.poll(localDate(0, 12, 24), weekendSchedule), null);
  assert.equal(weekdayScheduler.poll(localDate(0, 12, 26), weekendSchedule), null);
});

test('quiet hours work both across midnight and within one day', () => {
  const overnight = { enabled: true, start: '22:30', end: '08:30' };
  assert.equal(isInQuietHours(localDate(0, 23, 0), overnight), true);
  assert.equal(isInQuietHours(localDate(0, 8, 29), overnight), true);
  assert.equal(isInQuietHours(localDate(0, 12, 0), overnight), false);
  assert.equal(isInQuietHours(localDate(0, 12, 0), { enabled: false, start: '00:00', end: '00:00' }), false);
});
