const test = require('node:test');
const assert = require('node:assert/strict');
const { getScheduleReminder, isInQuietHours } = require('../src/core/reminder-scheduler');

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

test('quiet hours work both across midnight and within one day', () => {
  const overnight = { enabled: true, start: '22:30', end: '08:30' };
  assert.equal(isInQuietHours(localDate(0, 23, 0), overnight), true);
  assert.equal(isInQuietHours(localDate(0, 8, 29), overnight), true);
  assert.equal(isInQuietHours(localDate(0, 12, 0), overnight), false);
  assert.equal(isInQuietHours(localDate(0, 12, 0), { enabled: false, start: '00:00', end: '00:00' }), false);
});
