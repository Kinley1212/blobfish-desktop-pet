const { app, BrowserWindow, screen, ipcMain, Tray, Menu, nativeImage } = require('electron');
const path = require('path');
const { loadCharacterPack } = require('./core/pack-loader');
const { loadLanguagePack } = require('./core/language-pack-loader');
const { PhraseEngine } = require('./core/phrase-engine');
const { SpeechQueue } = require('./core/speech-queue');

const WINDOW_WIDTH = 340;
const WINDOW_HEIGHT = 210;
const SPEED = 1.5;
const TICK_MS = 30;
const CHARACTER_PACK_ID = 'blobfish';
const LANGUAGE_PACK_ID = 'blobfish-zh-TW';
const characterPack = loadCharacterPack(path.join(__dirname, 'packs', 'characters'), CHARACTER_PACK_ID);
const languagePack = loadLanguagePack(path.join(__dirname, 'packs', 'languages'), LANGUAGE_PACK_ID);
const phraseEngine = new PhraseEngine(languagePack.phrases);
const IDLE_CHATTER_MIN_MS = 12 * 60 * 1000;
const IDLE_CHATTER_MAX_MS = 35 * 60 * 1000;
const SPEECH_PRIORITY = Object.freeze({
  idle: 10,
  interaction: 30,
  schedule: 40,
  calendar: 50,
  agent: 60,
  urgent: 90,
});

// The visible fish only occupies a small box near the bottom-center of the
// (much larger) transparent window, which also has room for the speech
// bubble. Boundary checks are done against the fish's own box, not the
// window's, so dragging/walking can reach the true screen edges.
const PET_WIDTH = characterPack.manifest.size.width;
const PET_HEIGHT = characterPack.manifest.size.height;
const PET_BOTTOM_MARGIN = 10;
const PET_OFFSET_X = (WINDOW_WIDTH - PET_WIDTH) / 2;
const PET_TOP_MARGIN = WINDOW_HEIGHT - PET_BOTTOM_MARGIN - PET_HEIGHT;

// Release velocity (px/tick, after THROW_POWER amplification) needed before
// a drag-release counts as a fling instead of just a normal place-down.
// Deliberately high so an ordinary "pick up and put down" drag never fires
// this by accident - only a clear, fast flick should.
const FLING_MIN_SPEED = 14;
const MAX_FLING_SPEED = 55;
const FLING_FRICTION = 0.985;
const FLING_BOUNCE_DAMPING = 0.72;
const FLING_STOP_SPEED = 0.5;
const THROW_POWER = 1.35;

let win;
let tray;
let direction = 1;
let paused = false;
let currentY;
let flingIntervalId = null;
let speechQueue;
let idleChatterTimer = null;
let clickCount = 0;

function getDateContext(date = new Date()) {
  return {
    hour: date.getHours(),
    minute: date.getMinutes(),
    weekday: date.getDay(),
  };
}

function speak(event, context = {}, options = {}) {
  if (!speechQueue) return false;
  const phrase = phraseEngine.select(event, { ...getDateContext(), ...context });
  if (!phrase) return false;
  return speechQueue.enqueue({
    event,
    phraseId: phrase.id,
    text: phrase.text,
    priority: options.priority ?? SPEECH_PRIORITY.idle,
    durationMs: options.durationMs ?? 4000,
    replaceKey: options.replaceKey,
    action: options.action,
  });
}

function createTray() {
  tray = new Tray(nativeImage.createEmpty());
  tray.setTitle('🐟');
  tray.setToolTip('水滴魚桌寵');
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: '結束水滴魚', click: () => app.quit() },
  ]));
}

// Hard backstop: no real screen coordinate is ever remotely close to this,
// so anything beyond it can only be a bad computation upstream.
const MAX_COORD = 20000;

// Every window move ultimately funnels through here so a bad (non-finite,
// fractional, or absurdly large) coordinate can never reach the native
// setPosition binding and crash the main process.
function safeSetPosition(x, y) {
  if (!win || !Number.isFinite(x) || !Number.isFinite(y)) return;
  if (Math.abs(x) > MAX_COORD || Math.abs(y) > MAX_COORD) return;
  // Math.round(-0.5) is -0 in JS, and Electron's native setPosition binding
  // rejects negative zero outright ("conversion failure") - `|| 0` folds it
  // back to plain 0 without touching any other value.
  win.setPosition(Math.round(x) || 0, Math.round(y) || 0);
}

// The renderer normally toggles click-through by watching its own mousemove
// events, but that only fires when the *cursor* moves - when the *window*
// moves instead (autonomous swimming, flinging) the cursor can end up
// sitting right on top of the fish without any mousemove ever firing, so
// the stale "ignore" state never clears and clicks silently pass through.
// Called after every programmatic window move: hands the cursor's position
// (converted to window-local coordinates) to the renderer so it can re-run
// the exact same elementFromPoint hit-test it already uses for real mouse
// movement, instead of a second, separately-maintained approximation here.
function syncHoverState() {
  if (!win) return;
  const cursor = screen.getCursorScreenPoint();
  const [wx, wy] = win.getPosition();
  win.webContents.send('check-hover', cursor.x - wx, cursor.y - wy);
}

function isSaneRect(rect) {
  return (
    rect &&
    Number.isFinite(rect.x) &&
    Number.isFinite(rect.y) &&
    Number.isFinite(rect.width) &&
    Number.isFinite(rect.height) &&
    rect.width > 0 &&
    rect.height > 0 &&
    Math.abs(rect.x) <= MAX_COORD &&
    Math.abs(rect.y) <= MAX_COORD
  );
}

// Uses each display's workArea, not its full physical bounds: macOS silently
// clamps any window's position back to workArea.y whenever it would overlap
// the menu bar (confirmed experimentally - it ignores requests to go above
// it, even at high window levels), so computing against the physical bounds
// just makes our own tracked position disagree with where the window really
// ends up. workArea is what's actually reachable.
// Falls back to the primary display if the display list is empty or a
// display briefly reports bogus bounds (e.g. mid display-reconfiguration).
function getCombinedBounds() {
  const primary = screen.getPrimaryDisplay().workArea;
  const fallback = { minX: primary.x, minY: primary.y, maxX: primary.x + primary.width, maxY: primary.y + primary.height };

  const displays = screen.getAllDisplays().filter((d) => isSaneRect(d.workArea));
  if (displays.length === 0) return fallback;

  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;

  for (const display of displays) {
    const { x, y, width, height } = display.workArea;
    minX = Math.min(minX, x);
    minY = Math.min(minY, y);
    maxX = Math.max(maxX, x + width);
    maxY = Math.max(maxY, y + height);
  }

  if (!isSaneRect({ x: minX, y: minY, width: maxX - minX, height: maxY - minY })) {
    return fallback;
  }

  return { minX, minY, maxX, maxY };
}

function createWindow() {
  const { x: dispX, y: dispY, width: dispWidth, height: dispHeight } = screen.getPrimaryDisplay().workArea;
  currentY = Math.round(dispY + dispHeight - WINDOW_HEIGHT);

  win = new BrowserWindow({
    width: WINDOW_WIDTH,
    height: WINDOW_HEIGHT,
    x: Math.floor(dispX + dispWidth / 2),
    y: currentY,
    frame: false,
    transparent: true,
    alwaysOnTop: true,
    resizable: false,
    movable: false,
    skipTaskbar: true,
    hasShadow: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      sandbox: true,
    },
  });

  win.setAlwaysOnTop(true, 'screen-saver');
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  win.setIgnoreMouseEvents(true, { forward: true });
  win.webContents.on('console-message', (_event, _level, message) => {
    console.log('[renderer]', message);
  });
  win.loadFile(path.join(__dirname, 'index.html'));

  speechQueue = new SpeechQueue((message) => {
    if (win && !win.isDestroyed()) win.webContents.send('speech', message);
  });

  ipcMain.on('pause', (_event, value) => {
    paused = value;
  });

  ipcMain.on('set-ignore-mouse', (_event, ignore) => {
    win.setIgnoreMouseEvents(ignore, { forward: true });
  });

  ipcMain.on('pet-clicked', () => {
    clickCount += 1;
    speak('interaction.click', { clickCount }, {
      priority: SPEECH_PRIORITY.interaction,
      durationMs: 800,
      replaceKey: 'interaction.click',
    });

    if (clickCount >= 10 && Math.random() < 0.12) {
      speak('rare.tooManyClicks', { clickCount }, {
        priority: SPEECH_PRIORITY.interaction,
        durationMs: 4200,
        replaceKey: 'rare.tooManyClicks',
      });
    }
  });

  ipcMain.on('drag-start', () => {
    paused = true;
  });

  ipcMain.on('drag-move', (_event, dx, dy) => {
    if (!win) return;
    const [x, y] = win.getPosition();
    const { minX, minY, maxX, maxY } = getCombinedBounds();

    // The window's own top edge (not the fish's) is what macOS floors at
    // the menu bar, so the lower Y bound is minY itself - the PET_TOP_MARGIN
    // inset only helps at the bottom/left/right, where nothing stops the
    // window from extending past the fish into empty transparent space.
    const newX = Math.min(Math.max(x + dx, minX - PET_OFFSET_X), maxX - PET_OFFSET_X - PET_WIDTH);
    const newY = Math.min(Math.max(y + dy, minY), maxY - PET_TOP_MARGIN - PET_HEIGHT);
    safeSetPosition(newX, newY);
  });

  ipcMain.on('drag-end', (_event, vxPerMs, vyPerMs) => {
    if (!win) return;

    let vx = (vxPerMs || 0) * TICK_MS * THROW_POWER;
    let vy = (vyPerMs || 0) * TICK_MS * THROW_POWER;
    const speed = Math.hypot(vx, vy);

    if (!Number.isFinite(speed) || speed < FLING_MIN_SPEED) {
      currentY = win.getPosition()[1];
      paused = false;
      return;
    }

    if (speed > MAX_FLING_SPEED) {
      const scale = MAX_FLING_SPEED / speed;
      vx *= scale;
      vy *= scale;
    }

    startFling(vx, vy);
  });

  setInterval(() => {
    if (paused || flingIntervalId || !win) return;
    const [wx, wy] = win.getPosition();
    let nearestBounds = screen.getDisplayNearestPoint({
      x: wx + WINDOW_WIDTH / 2,
      y: wy + WINDOW_HEIGHT / 2,
    }).workArea;
    if (!isSaneRect(nearestBounds)) {
      nearestBounds = screen.getPrimaryDisplay().workArea;
    }
    const { x: areaX, width: areaWidth } = nearestBounds;

    let newX = wx + direction * SPEED;
    const minWinX = areaX - PET_OFFSET_X;
    const maxWinX = areaX + areaWidth - PET_OFFSET_X - PET_WIDTH;

    if (newX <= minWinX) {
      newX = minWinX;
      direction = 1;
      win.webContents.send('direction', direction);
    } else if (newX >= maxWinX) {
      newX = maxWinX;
      direction = -1;
      win.webContents.send('direction', direction);
    }

    safeSetPosition(newX, currentY);
  }, TICK_MS);

  win.webContents.once('did-finish-load', () => {
    scheduleReminders();
    scheduleIdleChatter();
  });
}

function startFling(vx, vy) {
  if (flingIntervalId) {
    clearInterval(flingIntervalId);
  }

  paused = true;
  let flingVX = vx;
  let flingVY = vy;

  flingIntervalId = setInterval(() => {
    if (!win) {
      clearInterval(flingIntervalId);
      flingIntervalId = null;
      return;
    }

    const [x, y] = win.getPosition();
    let newX = x + flingVX;
    let newY = y + flingVY;
    let bounced = false;

    const { minX, minY, maxX, maxY } = getCombinedBounds();
    const minWinX = minX - PET_OFFSET_X;
    const maxWinX = maxX - PET_OFFSET_X - PET_WIDTH;
    // Top uses minY directly (see drag-move above) - the window itself is
    // floored there by macOS, not just the fish inside it. The other three
    // edges keep the fish-relative inset since nothing stops the window
    // from extending past the fish into empty transparent space there.
    const minWinY = minY;
    const maxWinY = maxY - PET_TOP_MARGIN - PET_HEIGHT;

    if (newX <= minWinX) {
      newX = minWinX;
      flingVX = -flingVX * FLING_BOUNCE_DAMPING;
      bounced = true;
    } else if (newX >= maxWinX) {
      newX = maxWinX;
      flingVX = -flingVX * FLING_BOUNCE_DAMPING;
      bounced = true;
    }

    if (newY <= minWinY) {
      newY = minWinY;
      flingVY = -flingVY * FLING_BOUNCE_DAMPING;
      bounced = true;
    } else if (newY >= maxWinY) {
      newY = maxWinY;
      flingVY = -flingVY * FLING_BOUNCE_DAMPING;
      bounced = true;
    }

    safeSetPosition(newX, newY);

    const newDirection = flingVX >= 0 ? 1 : -1;
    if (newDirection !== direction) {
      direction = newDirection;
      win.webContents.send('direction', direction);
    }

    if (bounced) {
      win.webContents.send('bump');
    }

    flingVX *= FLING_FRICTION;
    flingVY *= FLING_FRICTION;

    const remainingSpeed = Math.hypot(flingVX, flingVY);
    if (!Number.isFinite(remainingSpeed) || remainingSpeed < FLING_STOP_SPEED) {
      clearInterval(flingIntervalId);
      flingIntervalId = null;
      currentY = Number.isFinite(newY) ? Math.round(newY) : win.getPosition()[1];
      paused = false;
      // Only re-check hover once, right as it comes to rest - calling this
      // on every single tick churned setIgnoreMouseEvents 30+ times a
      // second and seemed to race with real click delivery.
      syncHoverState();
    }
  }, TICK_MS);
}

function getReminder(date) {
  const hour = date.getHours();
  const minute = date.getMinutes();
  const day = date.getDay();

  if (hour === 12 && minute === 55) {
    return { event: 'schedule.lunchSoon' };
  }

  if (hour === 18 && minute === 55) {
    return { event: 'schedule.offWorkSoon', context: { farewell: day === 5 ? '下週見' : '明天見' } };
  }

  if (hour === 18 && minute === 30) {
    return { event: 'schedule.offWorkHalfHour' };
  }

  if (minute === 0 || minute === 30) {
    return { event: 'schedule.halfHour' };
  }

  return null;
}

function scheduleReminders() {
  function tick() {
    const now = new Date();
    const reminder = getReminder(now);
    if (reminder) {
      speak(reminder.event, reminder.context, {
        priority: SPEECH_PRIORITY.schedule,
        durationMs: 9000,
        replaceKey: reminder.event,
      });
    }
  }

  const now = new Date();
  const msUntilNextMinute = 60000 - (now.getSeconds() * 1000 + now.getMilliseconds());
  setTimeout(() => {
    tick();
    setInterval(tick, 60000);
  }, msUntilNextMinute);
}

function scheduleIdleChatter() {
  clearTimeout(idleChatterTimer);
  const delay = IDLE_CHATTER_MIN_MS + Math.random() * (IDLE_CHATTER_MAX_MS - IDLE_CHATTER_MIN_MS);
  idleChatterTimer = setTimeout(() => {
    if (paused || flingIntervalId) {
      scheduleIdleChatter();
      return;
    }
    const dateContext = getDateContext();
    let usedRareLine = false;
    if (Math.random() < 0.08) {
      const rareEvent = dateContext.hour <= 4 ? 'rare.lateNight' : 'rare.friday';
      usedRareLine = speak(rareEvent, dateContext, {
        priority: SPEECH_PRIORITY.idle,
        durationMs: 4500,
      });
    }
    if (!usedRareLine) {
      speak('idle.chatter', dateContext, {
        priority: SPEECH_PRIORITY.idle,
        durationMs: 4000,
        replaceKey: 'idle.chatter',
      });
    }
    scheduleIdleChatter();
  }, delay);
}

app.whenReady().then(() => {
  ipcMain.handle('character-pack:get', () => characterPack);
  createTray();
  createWindow();
});

app.on('window-all-closed', () => {
  app.quit();
});

app.on('before-quit', () => {
  clearTimeout(idleChatterTimer);
  if (speechQueue) speechQueue.clear();
});
