function timeToMinutes(value) {
  const [hours, minutes] = value.split(':').map(Number);
  return hours * 60 + minutes;
}

function minutesBefore(value, amount) {
  return (timeToMinutes(value) - amount + 24 * 60) % (24 * 60);
}

function minuteStart(date) {
  const value = new Date(date);
  value.setSeconds(0, 0);
  return value;
}

function minuteKey(date, event) {
  const pad = (value) => String(value).padStart(2, '0');
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
    pad(date.getHours()),
    pad(date.getMinutes()),
    event,
  ].join(':');
}

function getFarewell(day, workdays) {
  for (let offset = 1; offset <= 7; offset += 1) {
    if (!workdays.includes((day + offset) % 7)) continue;
    if (offset === 1) return '明天見';
    return day + offset >= 7 ? '下週見' : '下次見';
  }
  return '下次見';
}

function getScheduleReminder(date, schedule) {
  const day = date.getDay();
  if (!schedule.workdays.includes(day)) return null;

  const current = date.getHours() * 60 + date.getMinutes();
  if (schedule.lunchReminder && current === minutesBefore(schedule.lunchTime, 5)) {
    return { event: 'schedule.lunchSoon' };
  }
  if (schedule.offWorkReminder && current === minutesBefore(schedule.offWorkTime, 5)) {
    return { event: 'schedule.offWorkSoon', context: { farewell: getFarewell(day, schedule.workdays) } };
  }
  if (schedule.offWorkReminder && current === minutesBefore(schedule.offWorkTime, 30)) {
    return { event: 'schedule.offWorkHalfHour' };
  }
  if (schedule.halfHourReminders && (date.getMinutes() === 0 || date.getMinutes() === 30)) {
    return { event: 'schedule.halfHour' };
  }
  return null;
}

class ReminderScheduler {
  constructor(options = {}) {
    this.catchUpMinutes = Number.isInteger(options.catchUpMinutes)
      ? Math.max(0, options.catchUpMinutes)
      : 4;
    this.lastCheckedAt = null;
    this.deliveredKeys = new Set();
  }

  poll(date, schedule) {
    if (!(date instanceof Date) || Number.isNaN(date.getTime())) {
      throw new TypeError('A valid reminder poll date is required');
    }

    const currentMinute = minuteStart(date);
    let firstMinute = currentMinute;
    if (this.lastCheckedAt && currentMinute >= this.lastCheckedAt) {
      const earliestCatchUp = new Date(currentMinute.getTime() - this.catchUpMinutes * 60000);
      firstMinute = this.lastCheckedAt > earliestCatchUp ? this.lastCheckedAt : earliestCatchUp;
    }
    this.lastCheckedAt = currentMinute;

    let candidate = null;
    for (
      let cursor = minuteStart(firstMinute);
      cursor <= currentMinute;
      cursor = new Date(cursor.getTime() + 60000)
    ) {
      const reminder = getScheduleReminder(cursor, schedule);
      if (!reminder) continue;
      const key = minuteKey(cursor, reminder.event);
      if (!this.deliveredKeys.has(key)) candidate = { ...reminder, key };
    }
    if (!candidate) return null;

    this.deliveredKeys.add(candidate.key);
    if (this.deliveredKeys.size > 256) {
      this.deliveredKeys.delete(this.deliveredKeys.values().next().value);
    }
    const { key: _key, ...reminder } = candidate;
    return reminder;
  }
}

function isInQuietHours(date, quietHours) {
  if (!quietHours.enabled) return false;
  const current = date.getHours() * 60 + date.getMinutes();
  const start = timeToMinutes(quietHours.start);
  const end = timeToMinutes(quietHours.end);
  if (start === end) return true;
  return start < end ? current >= start && current < end : current >= start || current < end;
}

module.exports = {
  ReminderScheduler,
  getScheduleReminder,
  isInQuietHours,
  timeToMinutes,
};
