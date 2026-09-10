const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { CalendarEasterEggScheduler, dateEvent, rules } = require('../src/core/calendar-easter-eggs');
const flags = { enabled: true, quiet: false, busy: false };
const date = (time, day = '2026-09-10') => new Date(`${day}T${time}:00`);
const lunarNone = { formatToParts: () => [{ type: 'month', value: '2bis' }, { type: 'day', value: '1' }] };

test('primary times are exact, independent of random chance, and do not catch up', () => {
  const scheduler = new CalendarEasterEggScheduler({ random: () => 1 });
  for (const time of rules.primaryTimes) assert.equal(scheduler.poll(date(time), flags, () => true), rules.times[time]);
  assert.equal(scheduler.poll(date('13:14'), flags, () => true), null);
  assert.equal(scheduler.poll(date('13:15'), flags, () => true), null);
  assert.equal(new CalendarEasterEggScheduler().poll(date('13:15'), flags, () => true), null);
});

test('quiet, disabled and busy states neither speak nor consume an eligible moment', () => {
  const scheduler = new CalendarEasterEggScheduler();
  for (const disabled of [{ enabled: false }, { quiet: true }, { busy: true }]) {
    assert.equal(scheduler.poll(date('13:14'), { ...flags, ...disabled }, () => assert.fail('must not speak')), null);
  }
  assert.equal(scheduler.poll(date('13:14'), flags, () => false), null);
  assert.equal(scheduler.poll(date('13:14'), flags, () => true), 'rare.time1314');
});

test('ordinary times roll once and have a two-per-day quota without blocking 1314', () => {
  let rolls = 0;
  const miss = new CalendarEasterEggScheduler({ random: () => { rolls += 1; return 0.9; } });
  miss.poll(date('08:08'), flags, () => true);
  miss.poll(date('08:08'), flags, () => true);
  assert.equal(rolls, 1);
  const scheduler = new CalendarEasterEggScheduler({ random: () => 0 });
  assert.equal(scheduler.poll(date('08:08'), flags, () => true), 'rare.time0808');
  assert.equal(scheduler.poll(date('09:09'), flags, () => true), 'rare.time0909');
  assert.equal(scheduler.poll(date('11:11'), flags, () => true), null);
  assert.equal(scheduler.poll(date('13:14'), flags, () => true), 'rare.time1314');
  assert.equal(scheduler.poll(date('08:08', '2026-09-11'), flags, () => true), 'rare.time0808');
});

test('solar dates, leap days, month starts and real lunar festivals are matched', () => {
  for (const [md, event] of Object.entries(rules.solar)) {
    const year = md === '02-29' ? 2028 : 2026;
    assert.equal(dateEvent(date('12:00', `${year}-${md}`), lunarNone), event);
  }
  assert.equal(dateEvent(date('12:00', '2026-07-01'), lunarNone), 'rare.dateMonthStart');
  assert.equal(dateEvent(date('12:00', '2026-03-02'), lunarNone), null);
  for (const [day, event] of [['2026-02-17', 'rare.dateLunarNewYear'], ['2026-03-03', 'rare.dateLantern'], ['2026-09-25', 'rare.dateMidAutumn']]) {
    assert.equal(dateEvent(date('12:00', day)), event);
  }
  const leapFirstMonth = { formatToParts: () => [{ type: 'month', value: '1bis' }, { type: 'day', value: '1' }] };
  assert.equal(dateEvent(date('12:00', '2026-03-02'), leapFirstMonth), null);
});

test('date greetings wait for eligibility, persist across restarts, and never replay yesterday', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'fish-calendar-'));
  try {
    const options = { filePath: path.join(directory, 'state.json') };
    const scheduler = new CalendarEasterEggScheduler(options);
    assert.equal(scheduler.poll(date('08:30', '2026-12-25'), { ...flags, busy: true }, () => true), null);
    assert.equal(scheduler.poll(date('10:15', '2026-12-25'), flags, () => true), 'rare.dateChristmas');
    const reopened = new CalendarEasterEggScheduler(options);
    assert.equal(reopened.poll(date('10:16', '2026-12-25'), flags, () => true), null);
    assert.equal(reopened.poll(date('10:16', '2026-12-26'), flags, () => true), null);
    if (process.platform !== 'win32') assert.equal(fs.statSync(options.filePath).mode & 0o777, 0o600);
    fs.writeFileSync(options.filePath, '{bad json');
    assert.throws(() => new CalendarEasterEggScheduler(options));
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('every time and date rule has multilingual copy and matches native shared rules', () => {
  const { loadLanguagePack } = require('../src/core/language-pack-loader');
  const root = path.join(__dirname, '../src/packs/languages');
  const events = [...Object.values(rules.times), ...Object.values(rules.solar), ...Object.values(rules.lunar), rules.monthStart];
  for (const id of fs.readdirSync(root)) {
    const pack = loadLanguagePack(root, id);
    for (const event of events) assert.ok(pack.phrases.filter((p) => p.event === event).length >= 2, `${id}/${event}`);
  }
  const native = fs.readFileSync(path.join(__dirname, '../native-appkit/Sources/BlobfishNative/CalendarEasterEggs.swift'), 'utf8');
  assert.match(native, /calendar-easter-eggs\.json/);
  assert.match(native, /Calendar\(identifier: \.chinese\)/);
  assert.match(native, /lunarDate\.isLeapMonth != true/);
});

test('runtime wiring skips active alarms, conversations and uninitialized task tracking', () => {
  const vm = require('node:vm');
  const source = fs.readFileSync(path.join(__dirname, '../src/main.js'), 'utf8');
  const fn = source.slice(source.indexOf('function maybeSpeakCalendarEasterEgg(now)'), source.indexOf('function scheduleReminders()'));
  for (const extra of [
    { clockService: { getState: () => ({ alerts: [{ state: 'ringing' }] }) } },
    { dialogueWin: { isDestroyed: () => false, isVisible: () => true } },
    { taskTracker: null }, { currentAgentSnapshot: { activeCount: 1 } }, { lockedAt: 1 }, { flingIntervalId: 1 },
  ]) {
    let spoken = false;
    const context = { calendarEasterEggsDisabled: false,
      calendarEasterEggScheduler: { poll: (_, state, deliver) => { if (!state.busy) deliver('rare.time1314'); } },
      config: { language: { rareEnabled: true }, quietHours: {} }, isInQuietHours: () => false,
      taskTracker: {}, isIdleSpeechPaused: () => false, flingIntervalId: null, lockedAt: null,
      currentAgentSnapshot: { activeCount: 0 }, dialogueWin: null, clockService: null,
      speechQueue: { current: null, pending: [] }, SPEECH_PRIORITY: { idle: 10 },
      speak: () => { spoken = true; return true; }, console: { warn: () => assert.fail('unexpected error') }, ...extra };
    vm.runInNewContext(fn + ';maybeSpeakCalendarEasterEgg(new Date());', context);
    assert.equal(spoken, false);
  }
  const routine = fs.readFileSync(path.join(__dirname, '../native-appkit/Sources/BlobfishNative/RoutineService.swift'), 'utf8');
  assert.match(routine, /poll\(allowEasterEggs: false\)/);
  assert.match(routine, /busy: !allowEasterEggs \|\| routinePending/);
  const delegate = fs.readFileSync(path.join(__dirname, '../native-appkit/Sources/BlobfishNative/AppDelegate.swift'), 'utf8');
  assert.match(delegate, /self\.taskSnapshotReady && self\.panelController\.canPresentEasterEgg/);
});
