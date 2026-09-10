const fs = require('node:fs');
const path = require('node:path');
const rules = require('../packs/calendar-easter-eggs.json');
const pad = (value) => String(value).padStart(2, '0');
const fresh = (day = '') => ({ version: 1, day, attempted: [], dateDelivered: false, ordinaryCount: 0, lastOrdinaryAt: 0 });
function dateEvent(date, formatter = new Intl.DateTimeFormat('en-u-ca-chinese', { month: 'numeric', day: 'numeric' })) {
  const parts = Object.fromEntries(formatter.formatToParts(date).map(({ type, value }) => [type, value]));
  // Leap months have a suffix (for example 2bis); never treat them as the regular festival month.
  const lunar = /^\d+$/.test(parts.month) ? rules.lunar[`${Number(parts.month)}-${Number(parts.day)}`] : null;
  return lunar || rules.solar[`${pad(date.getMonth() + 1)}-${pad(date.getDate())}`]
    || (date.getDate() === 1 ? rules.monthStart : null);
}

class CalendarEasterEggScheduler {
  constructor({ filePath = null, random = Math.random } = {}) {
    this.filePath = filePath;
    this.random = random;
    this.state = fresh();
    if (!filePath) return;
    let stat;
    try { stat = fs.lstatSync(filePath); } catch (error) { if (error.code === 'ENOENT') return; throw error; }
    if (!stat.isFile() || stat.size > 16384 || (process.platform !== 'win32'
      && ((stat.mode & 0o077) !== 0 || stat.uid !== process.getuid()))) throw new Error('Unsafe calendar easter egg state');
    const state = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    if (state.version !== 1 || typeof state.day !== 'string' || state.day.length > 10
      || !Array.isArray(state.attempted) || state.attempted.length > 12
      || !state.attempted.every((event) => Object.values(rules.times).includes(event))
      || typeof state.dateDelivered !== 'boolean' || !Number.isInteger(state.ordinaryCount)
      || state.ordinaryCount < 0 || state.ordinaryCount > 2 || !Number.isFinite(state.lastOrdinaryAt)) {
      throw new Error('Invalid calendar easter egg state');
    }
    this.state = state;
  }

  save(state) {
    if (this.filePath) {
      fs.mkdirSync(path.dirname(this.filePath), { recursive: true, mode: 0o700 });
      const temporary = `${this.filePath}.${process.pid}.${require('node:crypto').randomUUID()}.tmp`;
      try {
        fs.writeFileSync(temporary, JSON.stringify(state), { flag: 'wx', mode: 0o600 });
        fs.renameSync(temporary, this.filePath);
      } finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
    }
    this.state = state;
  }

  poll(date, { enabled, quiet, busy }, deliver) {
    if (!(date instanceof Date) || !Number.isFinite(date.getTime())) throw new TypeError('Invalid easter egg date');
    if (!enabled || quiet || busy) return null;
    const day = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    const next = this.state.day === day ? { ...this.state, attempted: [...this.state.attempted] } : fresh(day);
    const time = `${pad(date.getHours())}:${pad(date.getMinutes())}`;
    const event = rules.times[time];
    const seconds = date.getTime() / 1000;
    if (event && !next.attempted.includes(event)) {
      const primary = rules.primaryTimes.includes(time);
      if (primary || (next.ordinaryCount < 2 && seconds - next.lastOrdinaryAt >= 3600)) {
        next.attempted.push(event);
        if (primary || this.random() < 0.25) {
          this.save({ ...next, ordinaryCount: next.ordinaryCount + (primary ? 0 : 1),
            lastOrdinaryAt: primary ? next.lastOrdinaryAt : seconds });
          if (deliver(event)) return event;
          next.attempted = next.attempted.filter((item) => item !== event);
          this.save(next);
          return null;
        }
        this.save(next);
      }
    }
    const dateEgg = dateEvent(date);
    if (!next.dateDelivered && dateEgg) {
      this.save({ ...next, dateDelivered: true });
      if (deliver(dateEgg)) return dateEgg;
      this.save(next);
    }
    return null;
  }
}

module.exports = { CalendarEasterEggScheduler, dateEvent, rules };
