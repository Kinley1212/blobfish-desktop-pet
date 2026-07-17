const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  StartupGreetingStore,
  getLocalDateKey,
  getStartupGreeting,
  validateState,
} = require('../src/core/startup-greeting');

const schedule = { workdays: [1, 2, 3, 4, 5] };
const greetings = {
  workday: { enabled: true, start: '07:00', end: '11:00' },
  dayOff: { enabled: true, start: '07:00', end: '18:00' },
};

test('selects the correct once-per-day greeting at inclusive and exclusive boundaries', () => {
  const fresh = { version: 1, lastGreetingDate: null };
  const mondayStart = new Date(2026, 6, 20, 7, 0);
  const mondayEnd = new Date(2026, 6, 20, 11, 0);
  const sunday = new Date(2026, 6, 19, 9, 30);

  assert.equal(getStartupGreeting(mondayStart, schedule, greetings, fresh).event, 'startup.workdayMorning');
  assert.equal(getStartupGreeting(mondayEnd, schedule, greetings, fresh), null);
  assert.equal(getStartupGreeting(sunday, schedule, greetings, fresh).event, 'startup.dayOff');

  const alreadyGreeted = { version: 1, lastGreetingDate: getLocalDateKey(mondayStart) };
  assert.equal(getStartupGreeting(mondayStart, schedule, greetings, alreadyGreeted), null);
});

test('disabled or out-of-range greetings remain silent', () => {
  const disabled = { ...greetings, workday: { ...greetings.workday, enabled: false } };
  assert.equal(getStartupGreeting(new Date(2026, 6, 20, 8, 0), schedule, disabled, { lastGreetingDate: null }), null);
  assert.equal(getStartupGreeting(new Date(2026, 6, 19, 6, 59), schedule, greetings, { lastGreetingDate: null }), null);
});

test('state validation rejects impossible calendar dates', () => {
  assert.throws(
    () => validateState({ version: 1, lastGreetingDate: '2026-02-30' }),
    /YYYY-MM-DD/,
  );
});

test('startup greeting store persists a private local-date marker and recovers from corrupt data', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-greeting-'));
  try {
    const store = new StartupGreetingStore(directory);
    assert.equal(store.load().lastGreetingDate, null);
    store.mark('2026-07-20');

    const reloaded = new StartupGreetingStore(directory);
    assert.equal(reloaded.load().lastGreetingDate, '2026-07-20');
    assert.equal(fs.statSync(reloaded.filePath).mode & 0o777, 0o600);

    fs.writeFileSync(reloaded.filePath, '{not json', 'utf8');
    assert.equal(reloaded.load().lastGreetingDate, null);
    assert.match(reloaded.loadWarning, /可能会重复问候/);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
