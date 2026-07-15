const { app, BrowserWindow, screen, ipcMain, Tray, Menu, nativeImage } = require('electron');
const path = require('path');

const WINDOW_WIDTH = 300;
const WINDOW_HEIGHT = 170;
const SPEED = 1.5;
const TICK_MS = 30;

// The visible fish only occupies a small box near the bottom-center of the
// (much larger) transparent window, which also has room for the speech
// bubble. Boundary checks are done against the fish's own box, not the
// window's, so dragging/walking can reach the true screen edges.
const PET_WIDTH = 82;
const PET_HEIGHT = 70;
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
    },
  });

  win.setAlwaysOnTop(true, 'screen-saver');
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  win.setIgnoreMouseEvents(true, { forward: true });
  win.webContents.on('console-message', (_event, _level, message) => {
    console.log('[renderer]', message);
  });
  win.loadFile(path.join(__dirname, 'index.html'));

  ipcMain.on('pause', (_event, value) => {
    paused = value;
  });

  ipcMain.on('set-ignore-mouse', (_event, ignore) => {
    win.setIgnoreMouseEvents(ignore, { forward: true });
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

  scheduleReminders();
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

function getReminderMessage(date) {
  const hour = date.getHours();
  const minute = date.getMinutes();
  const day = date.getDay();

  if (hour === 12 && minute === 55) {
    return '主人還有五分鐘就可以去吃飯啦，您辛苦啦。';
  }

  if (hour === 18 && minute === 55) {
    const farewell = day === 5 ? '下週見' : '明天見';
    return `主人還有五分鐘就下班啦，可以開始關閉軟件啦，記得先關梯子再關Claude喲。主人${farewell}～`;
  }

  if (hour === 18 && minute === 30) {
    return '主人還有半個鐘就下班啦，主人今天太棒啦！';
  }

  if (minute === 0 || minute === 30) {
    return '主人您辛苦了，您又工作了半小時。';
  }

  return null;
}

function scheduleReminders() {
  function tick() {
    const message = getReminderMessage(new Date());
    if (message && win) {
      win.webContents.send('reminder', message);
    }
  }

  const now = new Date();
  const msUntilNextMinute = 60000 - (now.getSeconds() * 1000 + now.getMilliseconds());
  setTimeout(() => {
    tick();
    setInterval(tick, 60000);
  }, msUntilNextMinute);
}

app.whenReady().then(() => {
  createTray();
  createWindow();
});

app.on('window-all-closed', () => {
  app.quit();
});
