function timeToMinutes(value) {
  const [hours, minutes] = value.split(':').map(Number);
  return hours * 60 + minutes;
}

function minutesBefore(value, amount) {
  return (timeToMinutes(value) - amount + 24 * 60) % (24 * 60);
}

function getScheduleReminder(date, schedule) {
  const day = date.getDay();
  if (!schedule.workdays.includes(day)) return null;

  const current = date.getHours() * 60 + date.getMinutes();
  if (schedule.lunchReminder && current === minutesBefore(schedule.lunchTime, 5)) {
    return { event: 'schedule.lunchSoon' };
  }
  if (schedule.offWorkReminder && current === minutesBefore(schedule.offWorkTime, 5)) {
    return { event: 'schedule.offWorkSoon', context: { farewell: day === 5 ? '下週見' : '明天見' } };
  }
  if (schedule.offWorkReminder && current === minutesBefore(schedule.offWorkTime, 30)) {
    return { event: 'schedule.offWorkHalfHour' };
  }
  if (schedule.halfHourReminders && (date.getMinutes() === 0 || date.getMinutes() === 30)) {
    return { event: 'schedule.halfHour' };
  }
  return null;
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
  getScheduleReminder,
  isInQuietHours,
  timeToMinutes,
};
