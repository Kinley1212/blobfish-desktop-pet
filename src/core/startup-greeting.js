const fs = require('fs');
const path = require('path');
const { timeToMinutes } = require('./reminder-scheduler');

const STATE_VERSION = 1;
const DATE_KEY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function pad(value) {
  return String(value).padStart(2, '0');
}

function getLocalDateKey(date) {
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) throw new TypeError('A valid date is required');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function isWithinRange(date, range) {
  const current = date.getHours() * 60 + date.getMinutes();
  return current >= timeToMinutes(range.start) && current < timeToMinutes(range.end);
}

function isValidDateKey(value) {
  if (typeof value !== 'string' || !DATE_KEY_PATTERN.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

function getStartupGreeting(date, schedule, greetings, state) {
  const dateKey = getLocalDateKey(date);
  if (state.lastGreetingDate === dateKey) return null;

  const isWorkday = schedule.workdays.includes(date.getDay());
  const range = isWorkday ? greetings.workday : greetings.dayOff;
  if (!range.enabled || !isWithinRange(date, range)) return null;

  return {
    event: isWorkday ? 'startup.workdayMorning' : 'startup.dayOff',
    dateKey,
    context: { hour: date.getHours(), minute: date.getMinutes(), weekday: date.getDay() },
  };
}

function validateState(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('state must be an object');
  if (value.version !== STATE_VERSION) throw new Error('unsupported state version');
  if (value.lastGreetingDate !== null && !isValidDateKey(value.lastGreetingDate)) {
    throw new Error('lastGreetingDate must use YYYY-MM-DD');
  }
  return { version: STATE_VERSION, lastGreetingDate: value.lastGreetingDate };
}

class StartupGreetingStore {
  constructor(directory, options = {}) {
    this.directory = directory;
    this.filePath = path.join(directory, options.filename || 'startup-greeting-state.json');
    this.state = { version: STATE_VERSION, lastGreetingDate: null };
    this.loadWarning = null;
  }

  load() {
    this.loadWarning = null;
    if (!fs.existsSync(this.filePath)) return this.get();
    try {
      this.state = validateState(JSON.parse(fs.readFileSync(this.filePath, 'utf8')));
    } catch (error) {
      this.state = { version: STATE_VERSION, lastGreetingDate: null };
      this.loadWarning = `首次问候记录无效，今天可能会重复问候：${error.message}`;
    }
    return this.get();
  }

  get() {
    return { ...this.state };
  }

  mark(dateKey) {
    const nextState = validateState({ version: STATE_VERSION, lastGreetingDate: dateKey });
    fs.mkdirSync(this.directory, { recursive: true, mode: 0o700 });
    const tempPath = `${this.filePath}.${process.pid}.tmp`;
    try {
      fs.writeFileSync(tempPath, `${JSON.stringify(nextState, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 });
      fs.renameSync(tempPath, this.filePath);
    } finally {
      if (fs.existsSync(tempPath)) fs.unlinkSync(tempPath);
    }
    this.state = nextState;
    return this.get();
  }
}

module.exports = {
  StartupGreetingStore,
  getLocalDateKey,
  getStartupGreeting,
  isValidDateKey,
  isWithinRange,
  validateState,
};
