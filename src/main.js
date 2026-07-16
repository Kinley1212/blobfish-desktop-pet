const { app, BrowserWindow, screen, ipcMain, Tray, Menu, nativeImage, powerMonitor, shell } = require('electron');
const fs = require('fs');
const path = require('path');
const { AgentBridge } = require('./core/agent-bridge');
const { BatteryThresholdTracker, readMacBattery } = require('./core/battery-monitor');
const { CalendarService } = require('./core/calendar-service');
const { ConnectionHealthTracker } = require('./core/connection-health');
const { ConfigStore, DEFAULT_CONFIG, validateConfig } = require('./core/config-store');
const { comparePluginVersions, IntegrationManager, PLUGIN_NAME } = require('./core/integration-manager');
const { loadCharacterPack } = require('./core/pack-loader');
const { loadLanguagePack } = require('./core/language-pack-loader');
const { calculateVerticalPlacement } = require('./core/pet-boundary');
const { PhraseEngine } = require('./core/phrase-engine');
const { getScheduleReminder, isInQuietHours } = require('./core/reminder-scheduler');
const { RuntimeErrorNotifier } = require('./core/runtime-error-notifier');
const { SpeechQueue } = require('./core/speech-queue');
const { SPEECH_DURATION_MS } = require('./core/speech-timing');
const { formatProviderTaskSummary } = require('./core/task-menu-summary');
const { advanceFractionalCoordinate, roundWindowCoordinate } = require('./core/fractional-position');
const { getCurrentTaskStatus, getTerminalTaskStatus } = require('./core/task-status-presenter');
const { TaskTracker } = require('./core/task-tracker');
const { version: appVersion } = require('../package.json');

const userDataRoot = app.getPath('appData');
const appRelease = appVersion.split('.').slice(0, 2).join('.');
const appDisplayName = `水滴鱼${appRelease}`;
app.setName(appDisplayName);
app.setPath('userData', path.join(userDataRoot, 'BlobfishDesktopPet'));
const hasSingleInstanceLock = app.requestSingleInstanceLock();
if (!hasSingleInstanceLock) app.quit();

const WINDOW_WIDTH = 340;
const WINDOW_HEIGHT = 210;
const TICK_MS = 30;
const EXIT_ANIMATION_MS = 1700;
const DEFAULT_CHARACTER_PACK_ID = 'blobfish';
const DEFAULT_LANGUAGE_PACK_ID = 'blobfish-zh-TW';
const CHARACTERS_ROOT = path.join(__dirname, 'packs', 'characters');
const LANGUAGES_ROOT = path.join(__dirname, 'packs', 'languages');
let characterPack = loadCharacterPack(CHARACTERS_ROOT, DEFAULT_CHARACTER_PACK_ID);
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
const PET_BOTTOM_MARGIN = 10;

function getPetMetrics() {
  const width = characterPack.manifest.size.width * config.pet.scale;
  const height = characterPack.manifest.size.height * config.pet.scale;
  return {
    width,
    height,
    offsetX: (WINDOW_WIDTH - width) / 2,
    topMargin: WINDOW_HEIGHT - PET_BOTTOM_MARGIN - height,
  };
}

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
let settingsWin;
let tray;
let direction = 1;
let paused = false;
let manuallyPaused = false;
let contextMenuPaused = false;
let systemPaused = false;
let agentPaused = false;
let currentX;
let currentY;
let petTopOffset = null;
let flingIntervalId = null;
let speechQueue;
let idleChatterTimer = null;
let clickCount = 0;
let configStore;
let config = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
let phraseEngine = null;
let runtimeWarning = null;
let batteryTracker;
let batteryPollTimer = null;
let batteryReadErrorLogged = false;
let calendarService;
let calendarStatus = 'disabled';
let lockedAt = null;
let lastWakeSpokenAt = 0;
let agentBridge;
let agentBridgeStatus = 'stopped';
let integrationManager;
let taskTracker;
let taskMaintenanceTimer = null;
let quitTimer = null;
let contextMenuPauseTimer = null;
let contextMenuSession = 0;
let lastContextMenuSpokenAt = 0;
let quitRequested = false;
let allowImmediateQuit = false;
let currentAgentSnapshot = Object.freeze({ activeCount: 0, waitingCount: 0, runningCount: 0 });
let runtimeErrorNotifier;
const connectionHealth = new ConnectionHealthTracker();
const longRunningNotified = new Set();

function getDateContext(date = new Date()) {
  return {
    hour: date.getHours(),
    minute: date.getMinutes(),
    weekday: date.getDay(),
  };
}

function listLanguagePacks() {
  return fs.readdirSync(LANGUAGES_ROOT, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      try {
        const pack = loadLanguagePack(LANGUAGES_ROOT, entry.name);
        return {
          id: pack.manifest.id,
          displayName: pack.manifest.displayName,
          locale: pack.manifest.locale,
          version: pack.manifest.version,
        };
      } catch (error) {
        console.error(`Ignoring invalid language pack ${entry.name}: ${error.message}`);
        return null;
      }
    })
    .filter(Boolean)
    .sort((a, b) => a.displayName.localeCompare(b.displayName));
}

function listCharacterPacks() {
  return fs.readdirSync(CHARACTERS_ROOT, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      try {
        const pack = loadCharacterPack(CHARACTERS_ROOT, entry.name);
        return {
          id: pack.manifest.id,
          displayName: pack.manifest.displayName,
          version: pack.manifest.version,
          preview: pack.manifest.preview,
          defaultLanguagePack: pack.manifest.defaultLanguagePack,
          settingsCopy: pack.settingsCopy,
        };
      } catch (error) {
        console.error(`Ignoring invalid character pack ${entry.name}: ${error.message}`);
        return null;
      }
    })
    .filter(Boolean)
    .sort((a, b) => a.displayName.localeCompare(b.displayName));
}

function loadConfiguredCharacter(packId) {
  try {
    characterPack = loadCharacterPack(CHARACTERS_ROOT, packId);
    return packId;
  } catch (error) {
    runtimeWarning = `形象包 ${packId} 无法加载，已临时改用默认形象：${error.message}`;
    reportRuntimeError('Character pack', error);
    characterPack = loadCharacterPack(CHARACTERS_ROOT, DEFAULT_CHARACTER_PACK_ID);
    return DEFAULT_CHARACTER_PACK_ID;
  }
}

function loadConfiguredLanguage(packId) {
  try {
    const pack = loadLanguagePack(LANGUAGES_ROOT, packId);
    phraseEngine = new PhraseEngine(pack.phrases);
    runtimeWarning = null;
    return packId;
  } catch (error) {
    runtimeWarning = `语言包 ${packId} 无法加载，已临时改用默认语言包：${error.message}`;
    reportRuntimeError('Language pack', error);
    const fallback = loadLanguagePack(LANGUAGES_ROOT, DEFAULT_LANGUAGE_PACK_ID);
    phraseEngine = new PhraseEngine(fallback.phrases);
    return DEFAULT_LANGUAGE_PACK_ID;
  }
}

function getEventCategory(event) {
  if (event.startsWith('schedule.')) return 'schedule';
  if (event.startsWith('system.')) return 'system';
  if (event.startsWith('calendar.')) return 'calendar';
  if (event.startsWith('agent.')) return 'agents';
  return null;
}

function isMovementPaused() {
  return paused || manuallyPaused || contextMenuPaused || systemPaused || agentPaused;
}

function isProviderEnabled(provider) {
  if (provider === 'codex') return config.integrations.codex;
  if (provider === 'claude-code') return config.integrations.claudeCode;
  return false;
}

function getConnectionProvider(provider) {
  return provider === 'claude-code' ? 'claude' : provider;
}

function emitConnectionHealth(provider) {
  if (!settingsWin || settingsWin.isDestroyed()) return;
  settingsWin.webContents.send('agent-connection-health', connectionHealth.snapshot(provider));
}

function speak(event, context = {}, options = {}) {
  if (!speechQueue || !phraseEngine) return false;
  const category = getEventCategory(event);
  if (category && !config.language.categories[category]) return false;
  const priority = options.priority ?? SPEECH_PRIORITY.idle;
  if (!options.allowDuringQuiet && priority < SPEECH_PRIORITY.urgent && isInQuietHours(new Date(), config.quietHours)) {
    return false;
  }
  const phrase = phraseEngine.select(event, { ...getDateContext(), ...context });
  if (!phrase) return false;
  return speechQueue.enqueue({
    event,
    phraseId: phrase.id,
    text: phrase.text,
    priority,
    durationMs: options.durationMs ?? 4000,
    replaceKey: options.replaceKey,
    action: options.action,
  });
}

runtimeErrorNotifier = new RuntimeErrorNotifier(() => speak('system.error', {}, {
  priority: SPEECH_PRIORITY.urgent,
  durationMs: 5500,
  replaceKey: 'system.error',
  allowDuringQuiet: true,
  action: 'failed',
}));

function reportRuntimeError(scope, error) {
  return runtimeErrorNotifier.report(scope, error);
}

function syncLaunchAtLogin(enabled) {
  app.setLoginItemSettings({ openAtLogin: enabled });
  const actual = app.getLoginItemSettings().openAtLogin;
  if (actual !== enabled) throw new Error('macOS 未能更新登录时自动启动设置');
}

function requestQuit() {
  if (quitRequested) return;
  quitRequested = true;
  manuallyPaused = true;
  rebuildTrayMenu();
  if (win && !win.isDestroyed()) {
    win.webContents.send('pet-action', { action: 'exit', durationMs: EXIT_ANIMATION_MS });
  }
  const spoken = speak('interaction.goodbye', {}, {
    priority: SPEECH_PRIORITY.urgent,
    durationMs: 1800,
    replaceKey: 'interaction.goodbye',
    allowDuringQuiet: true,
  });
  quitTimer = setTimeout(() => {
    allowImmediateQuit = true;
    app.quit();
  }, Math.max(EXIT_ANIMATION_MS + 150, spoken ? 1900 : 0));
}

function toggleManualPause(checked) {
  if (manuallyPaused === checked) return;
  manuallyPaused = checked;
  speak(checked ? 'interaction.paused' : 'interaction.resumed', {}, {
    priority: SPEECH_PRIORITY.interaction,
    durationMs: 2800,
    replaceKey: 'interaction.movementToggle',
    allowDuringQuiet: true,
  });
  rebuildTrayMenu();
}

function buildPetMenuTemplate() {
  const tasks = taskTracker ? taskTracker.getTasks() : [];
  return [
    { label: '任务状态', enabled: false },
    {
      label: formatProviderTaskSummary(tasks, 'codex', 'Codex', config.integrations.codex),
      enabled: false,
    },
    {
      label: formatProviderTaskSummary(tasks, 'claude-code', 'Claude', config.integrations.claudeCode),
      enabled: false,
    },
    { type: 'separator' },
    { label: '打开设置…', click: () => createSettingsWindow() },
    {
      label: manuallyPaused ? '继续游动' : '暂停游动',
      click: () => toggleManualPause(!manuallyPaused),
    },
    {
      label: '登录后自动启动',
      type: 'checkbox',
      checked: config.startup.launchAtLogin,
      click: (item) => {
        const previous = config.startup.launchAtLogin;
        try {
          syncLaunchAtLogin(item.checked);
          config = configStore.save({
            ...config,
            startup: { ...config.startup, launchAtLogin: item.checked },
          });
        } catch (error) {
          try { syncLaunchAtLogin(previous); } catch {}
          console.error(error.message);
        }
        rebuildTrayMenu();
      },
    },
    { type: 'separator' },
    { label: `退出${appDisplayName}`, click: () => requestQuit() },
  ];
}

function rebuildTrayMenu() {
  if (!tray) return;
  tray.setContextMenu(Menu.buildFromTemplate(buildPetMenuTemplate()));
}

function createTray() {
  tray = new Tray(nativeImage.createEmpty());
  tray.setTitle('🐟');
  tray.setToolTip(appDisplayName);
  rebuildTrayMenu();
}

function createApplicationMenu() {
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    {
      label: app.name,
      submenu: [
        { label: '设置…', accelerator: 'CmdOrCtrl+,', click: () => createSettingsWindow() },
        { type: 'separator' },
        { label: `退出${appDisplayName}`, accelerator: 'CmdOrCtrl+Q', click: () => requestQuit() },
      ],
    },
    { role: 'editMenu' },
    { role: 'windowMenu' },
  ]));
}

function createSettingsWindow() {
  if (settingsWin && !settingsWin.isDestroyed()) {
    settingsWin.show();
    settingsWin.focus();
    return;
  }

  settingsWin = new BrowserWindow({
    width: 620,
    height: 760,
    minWidth: 520,
    minHeight: 620,
    title: '水滴鱼设置',
    backgroundColor: '#f2f0ec',
    webPreferences: {
      preload: path.join(__dirname, 'settings-preload.js'),
      contextIsolation: true,
      sandbox: true,
    },
  });
  settingsWin.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  settingsWin.on('closed', () => { settingsWin = null; });
  settingsWin.loadFile(path.join(__dirname, 'settings.html'));
}

function revealExistingInstance() {
  if (app.isReady()) {
    createSettingsWindow();
    return;
  }
  app.whenReady().then(() => createSettingsWindow());
}

function assertSettingsSender(event) {
  if (!settingsWin || settingsWin.isDestroyed() || event.sender.id !== settingsWin.webContents.id) {
    throw new Error('Settings request came from an untrusted window');
  }
}

function getSettingsPayload() {
  return {
    config: JSON.parse(JSON.stringify(config)),
    characters: listCharacterPacks(),
    languages: listLanguagePacks(),
    warning: runtimeWarning || configStore.loadWarning,
    integrationStatus: { calendar: calendarStatus, agentBridge: agentBridgeStatus },
  };
}

function getIntegrationResourcesRoot() {
  if (app.isPackaged) return path.join(process.resourcesPath, 'integrations');
  return path.join(__dirname, '..', 'integrations');
}

function applyConfig(nextConfig) {
  const characterChanged = nextConfig.pet.characterPackId !== config.pet.characterPackId;
  const sizeChanged = characterChanged || nextConfig.pet.scale !== config.pet.scale;
  const languageChanged = !phraseEngine || nextConfig.language.packId !== config.language.packId;
  let previousPetPosition = null;
  if (sizeChanged && win && !win.isDestroyed()) {
    const [x, y] = win.getPosition();
    const oldMetrics = getPetMetrics();
    previousPetPosition = {
      x,
      top: y + (Number.isFinite(petTopOffset) ? petTopOffset : oldMetrics.topMargin),
    };
  }
  config = nextConfig;
  if (characterChanged) loadConfiguredCharacter(config.pet.characterPackId);
  if (languageChanged) loadConfiguredLanguage(config.language.packId);
  if (calendarService) calendarService.setEnabled(config.integrations.calendar);
  if (taskTracker) {
    if (!config.integrations.codex) taskTracker.removeProvider('codex');
    if (!config.integrations.claudeCode) taskTracker.removeProvider('claude-code');
    updateAgentState(taskTracker.snapshot());
    emitTaskStatus();
  }
  if (win && !win.isDestroyed()) {
    if (previousPetPosition) {
      const placement = calculateVerticalPlacement(previousPetPosition.top, getCombinedBounds(), getPetMetrics());
      petTopOffset = placement.topOffset;
      currentY = placement.windowY;
      safeSetPosition(previousPetPosition.x, placement.windowY);
    }
    if (characterChanged) win.webContents.send('character-pack', characterPack);
    win.webContents.send('pet-config', { scale: config.pet.scale, ...getPetLayoutPayload() });
    syncHoverState();
  }
  scheduleIdleChatter();
}

function persistConfig(nextConfig) {
  const validated = validateConfig(nextConfig);
  const previousLaunchAtLogin = config.startup.launchAtLogin;
  if (validated.startup.launchAtLogin !== previousLaunchAtLogin) {
    syncLaunchAtLogin(validated.startup.launchAtLogin);
  }
  try {
    return configStore.save(validated);
  } catch (error) {
    if (validated.startup.launchAtLogin !== previousLaunchAtLogin) {
      try { syncLaunchAtLogin(previousLaunchAtLogin); } catch {}
    }
    throw error;
  }
}

function showPetContextMenu(event) {
  if (!win || win.isDestroyed() || event.sender.id !== win.webContents.id) return;
  clearTimeout(contextMenuPauseTimer);
  const session = ++contextMenuSession;
  contextMenuPaused = true;
  const now = Date.now();
  if (now - lastContextMenuSpokenAt >= 5 * 60 * 1000 && Math.random() < 0.25) {
    const spoken = speak('interaction.menuOpen', {}, {
      priority: SPEECH_PRIORITY.interaction,
      durationMs: 2800,
      replaceKey: 'interaction.menuOpen',
      allowDuringQuiet: true,
    });
    if (spoken) lastContextMenuSpokenAt = now;
  }
  Menu.buildFromTemplate(buildPetMenuTemplate()).popup({
    window: win,
    callback: () => {
      if (session !== contextMenuSession) return;
      contextMenuPauseTimer = setTimeout(() => {
        if (session === contextMenuSession) contextMenuPaused = false;
      }, 300);
    },
  });
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
  win.setPosition(roundWindowCoordinate(x), roundWindowCoordinate(y));
}

function getPetLayoutPayload() {
  const metrics = getPetMetrics();
  const rawTopOffset = Number.isFinite(petTopOffset) ? petTopOffset : metrics.topMargin;
  const topOffset = Math.min(metrics.topMargin, Math.max(0, rawTopOffset));
  return {
    topOffset,
    bubblePlacement: topOffset < Math.min(64, metrics.topMargin * 0.62) ? 'below' : 'above',
  };
}

function syncPetLayout(force = false) {
  if (!win || win.isDestroyed()) return;
  const payload = getPetLayoutPayload();
  if (!force && payload.topOffset === syncPetLayout.lastTopOffset
    && payload.bubblePlacement === syncPetLayout.lastBubblePlacement) return;
  syncPetLayout.lastTopOffset = payload.topOffset;
  syncPetLayout.lastBubblePlacement = payload.bubblePlacement;
  win.webContents.send('pet-layout', payload);
}

function positionPetAt(x, desiredPetTop, bounds = getCombinedBounds()) {
  const placement = calculateVerticalPlacement(desiredPetTop, bounds, getPetMetrics());
  petTopOffset = placement.topOffset;
  safeSetPosition(x, placement.windowY);
  syncPetLayout();
  return placement;
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

let lastAutomaticHoverSyncAt = 0;
function syncAutomaticHoverState(now = Date.now()) {
  if (now - lastAutomaticHoverSyncAt < 120) return;
  lastAutomaticHoverSyncAt = now;
  syncHoverState();
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
  currentX = Math.floor(dispX + dispWidth / 2);
  currentY = Math.round(dispY + dispHeight - WINDOW_HEIGHT);
  petTopOffset = getPetMetrics().topMargin;

  win = new BrowserWindow({
    width: WINDOW_WIDTH,
    height: WINDOW_HEIGHT,
    x: currentX,
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
      allowDuringQuiet: true,
    });

    if (config.language.rareEnabled && clickCount >= 10 && Math.random() < 0.12) {
      speak('rare.tooManyClicks', { clickCount }, {
        priority: SPEECH_PRIORITY.interaction,
        durationMs: 4200,
        replaceKey: 'rare.tooManyClicks',
        allowDuringQuiet: true,
      });
    }
  });

  ipcMain.on('pet-context-menu', showPetContextMenu);

  ipcMain.on('drag-start', () => {
    paused = true;
    currentX = win ? win.getPosition()[0] : currentX;
  });

  ipcMain.on('drag-move', (_event, dx, dy) => {
    if (!win) return;
    const [x, y] = win.getPosition();
    const { minX, minY, maxX, maxY } = getCombinedBounds();
    const petMetrics = getPetMetrics();

    const newX = Math.min(Math.max(x + dx, minX - petMetrics.offsetX), maxX - petMetrics.offsetX - petMetrics.width);
    currentX = newX;
    const currentPetTop = y + (Number.isFinite(petTopOffset) ? petTopOffset : petMetrics.topMargin);
    positionPetAt(newX, currentPetTop + dy, { minY, maxY });
  });

  ipcMain.on('drag-end', (_event, vxPerMs, vyPerMs) => {
    if (!win) return;

    let vx = (vxPerMs || 0) * TICK_MS * THROW_POWER;
    let vy = (vyPerMs || 0) * TICK_MS * THROW_POWER;
    const speed = Math.hypot(vx, vy);

    if (!Number.isFinite(speed) || speed < FLING_MIN_SPEED) {
      [currentX, currentY] = win.getPosition();
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
    if (isMovementPaused() || flingIntervalId || !win) return;
    const [wx, wy] = win.getPosition();
    let nearestBounds = screen.getDisplayNearestPoint({
      x: wx + WINDOW_WIDTH / 2,
      y: wy + WINDOW_HEIGHT / 2,
    }).workArea;
    if (!isSaneRect(nearestBounds)) {
      nearestBounds = screen.getPrimaryDisplay().workArea;
    }
    const { x: areaX, width: areaWidth } = nearestBounds;
    const petMetrics = getPetMetrics();

    let newX = advanceFractionalCoordinate(currentX, wx, direction * config.pet.speed);
    const minWinX = areaX - petMetrics.offsetX;
    const maxWinX = areaX + areaWidth - petMetrics.offsetX - petMetrics.width;

    if (newX <= minWinX) {
      newX = minWinX;
      direction = 1;
      win.webContents.send('direction', direction);
    } else if (newX >= maxWinX) {
      newX = maxWinX;
      direction = -1;
      win.webContents.send('direction', direction);
    }

    currentX = newX;
    safeSetPosition(newX, currentY);
    syncAutomaticHoverState();
  }, TICK_MS);

  win.webContents.once('did-finish-load', () => {
    runtimeErrorNotifier.setReady();
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
    const currentPetTop = y + (Number.isFinite(petTopOffset) ? petTopOffset : getPetMetrics().topMargin);
    let newPetTop = currentPetTop + flingVY;
    let bounced = false;

    const { minX, minY, maxX, maxY } = getCombinedBounds();
    const petMetrics = getPetMetrics();
    const minWinX = minX - petMetrics.offsetX;
    const maxWinX = maxX - petMetrics.offsetX - petMetrics.width;

    if (newX <= minWinX) {
      newX = minWinX;
      flingVX = -flingVX * FLING_BOUNCE_DAMPING;
      bounced = true;
    } else if (newX >= maxWinX) {
      newX = maxWinX;
      flingVX = -flingVX * FLING_BOUNCE_DAMPING;
      bounced = true;
    }

    const verticalPlacement = calculateVerticalPlacement(newPetTop, { minY, maxY }, petMetrics);
    if (verticalPlacement.hitTop) {
      newPetTop = verticalPlacement.petTop;
      flingVY = -flingVY * FLING_BOUNCE_DAMPING;
      bounced = true;
    } else if (verticalPlacement.hitBottom) {
      newPetTop = verticalPlacement.petTop;
      flingVY = -flingVY * FLING_BOUNCE_DAMPING;
      bounced = true;
    }

    const positioned = positionPetAt(newX, newPetTop, { minY, maxY });
    syncAutomaticHoverState();

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
      [currentX, currentY] = win.getPosition();
      if (Number.isFinite(positioned.windowY)) currentY = roundWindowCoordinate(positioned.windowY);
      paused = false;
      // Only re-check hover once, right as it comes to rest - calling this
      // on every single tick churned setIgnoreMouseEvents 30+ times a
      // second and seemed to race with real click delivery.
      syncHoverState();
    }
  }, TICK_MS);
}

function scheduleReminders() {
  function tick() {
    const now = new Date();
    const reminder = getScheduleReminder(now, config.schedule);
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
  if (!config.language.idleEnabled) return;
  const minMs = config.language.idleMinMinutes * 60 * 1000;
  const maxMs = config.language.idleMaxMinutes * 60 * 1000;
  const delay = minMs + Math.random() * (maxMs - minMs);
  idleChatterTimer = setTimeout(() => {
    if (isMovementPaused() || flingIntervalId) {
      scheduleIdleChatter();
      return;
    }
    const dateContext = getDateContext();
    let usedRareLine = false;
    if (config.language.rareEnabled && Math.random() < 0.08) {
      const rareEvent = dateContext.hour <= 4 ? 'rare.lateNight' : 'rare.friday';
      usedRareLine = speak(rareEvent, dateContext, {
        priority: SPEECH_PRIORITY.idle,
        durationMs: SPEECH_DURATION_MS.idleChatter,
      });
    }
    if (!usedRareLine) {
      speak('idle.chatter', dateContext, {
        priority: SPEECH_PRIORITY.idle,
        durationMs: SPEECH_DURATION_MS.idleChatter,
        replaceKey: 'idle.chatter',
      });
    }
    scheduleIdleChatter();
  }, delay);
}

function pollBattery() {
  readMacBattery()
    .then((sample) => {
      batteryReadErrorLogged = false;
      batteryTracker.update(sample);
    })
    .catch((error) => {
      if (!batteryReadErrorLogged) {
        console.error(error.message);
        batteryReadErrorLogged = true;
      }
    });
}

function speakAfterWake() {
  const now = Date.now();
  if (now - lastWakeSpokenAt < 2000) return;
  lastWakeSpokenAt = now;
  const lockedSeconds = lockedAt ? Math.max(0, Math.round((now - lockedAt) / 1000)) : 0;
  lockedAt = null;
  systemPaused = false;
  speak('system.unlocked', { lockedSeconds }, {
    priority: 70,
    durationMs: 4500,
    replaceKey: 'system.unlocked',
  });
  if (config.language.rareEnabled && lockedSeconds >= 7200) {
    speak('rare.returnAfterLongLock', { lockedSeconds }, {
      priority: 70,
      durationMs: 5000,
      replaceKey: 'rare.returnAfterLongLock',
    });
  }
}

function setupSystemMonitors() {
  batteryTracker = new BatteryThresholdTracker((threshold) => {
    speak('system.battery', { battery: threshold }, {
      priority: SPEECH_PRIORITY.urgent,
      durationMs: 10000,
      replaceKey: 'system.battery',
      allowDuringQuiet: true,
      action: 'waiting',
    });
  });
  pollBattery();
  batteryPollTimer = setInterval(pollBattery, 60 * 1000);

  powerMonitor.on('on-ac', pollBattery);
  powerMonitor.on('on-battery', pollBattery);
  powerMonitor.on('lock-screen', () => {
    systemPaused = true;
    lockedAt = Date.now();
  });
  powerMonitor.on('unlock-screen', speakAfterWake);
  powerMonitor.on('suspend', () => {
    systemPaused = true;
    if (!lockedAt) lockedAt = Date.now();
  });
  powerMonitor.on('resume', speakAfterWake);
}

function getCalendarHelperPath() {
  if (app.isPackaged) return path.join(process.resourcesPath, 'native', 'blobfish-calendar-helper');
  return path.join(__dirname, '..', 'native', 'build', process.arch, 'blobfish-calendar-helper');
}

function handleCalendarEvent(calendarEvent) {
  const context = {};
  if (calendarEvent.event && config.privacy.includeCalendarTitles && calendarEvent.event.title) {
    context.title = calendarEvent.event.title;
  }
  if (calendarEvent.minutes) context.minutes = calendarEvent.minutes;

  const eventName = {
    upcoming: 'calendar.upcoming',
    starting: 'calendar.starting',
    busyDay: 'calendar.busyDay',
  }[calendarEvent.type];
  if (!eventName) return;
  speak(eventName, context, {
    priority: SPEECH_PRIORITY.calendar,
    durationMs: calendarEvent.type === 'starting' ? 7000 : 5500,
    replaceKey: eventName,
  });
}

function setupCalendarService() {
  calendarService = new CalendarService({
    helperPath: getCalendarHelperPath(),
    onEvent: handleCalendarEvent,
    onStatus: (status, error) => {
      calendarStatus = status;
      if (error) reportRuntimeError('Calendar integration', error);
      if (settingsWin && !settingsWin.isDestroyed()) {
        settingsWin.webContents.send('integration-status', { calendar: status, agentBridge: agentBridgeStatus });
      }
    },
  });
  calendarService.setEnabled(config.integrations.calendar);
}

function updateAgentState(snapshot) {
  currentAgentSnapshot = snapshot;
  rebuildTrayMenu();
  const allWaiting = snapshot.activeCount > 0 && snapshot.waitingCount === snapshot.activeCount;
  agentPaused = allWaiting || (snapshot.activeCount === 0 && !config.pet.roamWhenNoTasks);
  const motion = snapshot.activeCount > 0
    ? (allWaiting ? 'waiting' : 'working')
    : (agentPaused ? 'idle' : 'roam');
  if (win && !win.isDestroyed()) {
    win.webContents.send('agent-state', { ...snapshot, motion });
  }
}

function getVisibleTaskStatus() {
  return getCurrentTaskStatus(
    taskTracker ? taskTracker.getTasks() : [],
    config.privacy.includeTaskTitles,
  );
}

function emitTaskStatus(status = getVisibleTaskStatus()) {
  if (win && !win.isDestroyed()) win.webContents.send('task-status', status);
}

function handleTaskTransition(transition) {
  updateAgentState(transition.snapshot);
  const terminalState = transition.type === 'failed'
    ? 'failed'
    : ['completed', 'allCompleted'].includes(transition.type)
      ? 'completed'
      : ['ended', 'allEnded'].includes(transition.type)
        ? 'ended'
      : null;
  if (terminalState) {
    emitTaskStatus(getTerminalTaskStatus(
      transition.task,
      terminalState,
      taskTracker.getTasks(),
      config.privacy.includeTaskTitles,
    ));
  } else {
    emitTaskStatus();
  }
  const context = {
    activeCount: transition.snapshot.activeCount,
    remaining: transition.snapshot.activeCount,
    provider: transition.event?.provider,
  };
  const speechOptions = {
    priority: SPEECH_PRIORITY.agent,
    durationMs: SPEECH_DURATION_MS.agentLifecycle,
  };

  if (transition.type === 'started') {
    speak('agent.started', context, { ...speechOptions, replaceKey: 'agent.started' });
  } else if (transition.type === 'needsInput') {
    speak('agent.needsInput', context, {
      priority: SPEECH_PRIORITY.urgent,
      durationMs: SPEECH_DURATION_MS.agentLifecycle,
      replaceKey: 'agent.needsInput',
      allowDuringQuiet: true,
      action: 'waiting',
    });
  } else if (transition.type === 'completed') {
    speak('agent.completed', context, { ...speechOptions, replaceKey: 'agent.completed', action: 'success' });
  } else if (transition.type === 'allCompleted') {
    speak('agent.allCompleted', context, {
      ...speechOptions,
      replaceKey: 'agent.allCompleted',
      action: 'success',
    });
  } else if (transition.type === 'ended') {
    speak('agent.ended', context, { ...speechOptions, replaceKey: 'agent.ended' });
  } else if (transition.type === 'allEnded') {
    speak('agent.allEnded', context, {
      ...speechOptions,
      replaceKey: 'agent.allEnded',
    });
  } else if (transition.type === 'failed') {
    speak('agent.failed', context, {
      priority: SPEECH_PRIORITY.urgent,
      durationMs: SPEECH_DURATION_MS.agentLifecycle,
      replaceKey: 'agent.failed',
      allowDuringQuiet: true,
      action: 'failed',
    });
  }
}

function runTaskMaintenance() {
  taskTracker.pruneStale(12 * 60 * 60 * 1000);
  const now = Date.now();
  const activeKeys = new Set();
  for (const task of taskTracker.getTasks()) {
    activeKeys.add(task.key);
    const durationSeconds = Math.floor((now - task.startedAt) / 1000);
    if (durationSeconds >= 20 * 60 && !longRunningNotified.has(task.key)) {
      longRunningNotified.add(task.key);
      speak('agent.longRunning', { durationSeconds, provider: task.provider }, {
        priority: SPEECH_PRIORITY.agent,
        durationMs: 5500,
        replaceKey: 'agent.longRunning',
      });
    }
  }
  for (const key of longRunningNotified) {
    if (!activeKeys.has(key)) longRunningNotified.delete(key);
  }
}

function setupAgentBridge() {
  taskTracker = new TaskTracker(handleTaskTransition);
  updateAgentState(taskTracker.snapshot());
  emitTaskStatus();
  agentBridge = new AgentBridge(path.join(app.getPath('userData'), 'agent-events.sock'), {
    onEvent: (event) => {
      const connectionProvider = getConnectionProvider(event.provider);
      connectionHealth.noteEvent(connectionProvider);
      emitConnectionHealth(connectionProvider);
      if (isProviderEnabled(event.provider)) taskTracker.handle(event);
    },
    onError: (error) => reportRuntimeError('Agent bridge', error),
  });
  agentBridgeStatus = 'starting';
  agentBridge.start()
    .then(() => {
      agentBridgeStatus = 'listening';
      if (settingsWin && !settingsWin.isDestroyed()) {
        settingsWin.webContents.send('integration-status', { calendar: calendarStatus, agentBridge: agentBridgeStatus });
      }
    })
    .catch((error) => {
      agentBridgeStatus = 'error';
      reportRuntimeError('Agent bridge', error);
    });
  taskMaintenanceTimer = setInterval(runTaskMaintenance, 5 * 60 * 1000);
}

async function connectAgentIntegration(provider, force = false) {
  try {
    let status = null;
    if (provider === 'codex') {
      status = await integrationManager.inspect('codex');
      if (status.state === 'cli-missing') {
        const prepared = integrationManager.prepare('codex');
        const installUrl = `codex://plugins/${PLUGIN_NAME}?marketplacePath=${encodeURIComponent(prepared.marketplacePath)}`;
        await shell.openExternal(installUrl);
        return {
          provider,
          state: 'opened',
          cliFound: false,
          installed: false,
          enabled: false,
          changed: false,
          restartRequired: true,
          trustRequired: true,
          operation: force ? 'repair' : 'install',
        };
      }
    }
    if (provider === 'claude') {
      status = await integrationManager.inspect('claude');
      if (status.state === 'connected' && !force) return { ...status, changed: false, restartRequired: false };
      const operation = status.state === 'legacy' ? 'migrate' : force ? 'repair' : 'install';
      const prepared = integrationManager.prepareClaudeTerminalAction(process.execPath, operation);
      const openError = await shell.openPath(prepared.commandPath);
      if (openError) throw new Error(`无法打开 Terminal 安装窗口：${openError}`);
      if (operation === 'migrate') {
        connectionHealth.clear(provider);
        emitConnectionHealth(provider);
      }
      return {
        provider,
        state: 'terminal-opened',
        cliFound: true,
        installed: status.installed,
        enabled: status.enabled,
        changed: false,
        restartRequired: true,
        operation,
      };
    }
    const migrating = status?.state === 'legacy';
    if (migrating) {
      connectionHealth.clear(provider);
      emitConnectionHealth(provider);
    }
    const result = migrating
      ? await integrationManager.migrateLegacy(provider)
      : force
        ? await integrationManager.repair(provider)
        : await integrationManager.install(provider);
    if (result.changed) {
      speak('system.integrationReady', { provider }, {
        priority: SPEECH_PRIORITY.agent,
        durationMs: 5000,
        replaceKey: 'system.integrationReady',
        allowDuringQuiet: true,
      });
    }
    return result;
  } catch (error) {
    reportRuntimeError(`${provider} connection`, error);
    throw error;
  }
}

async function disconnectAgentIntegration(provider) {
  try {
    if (provider === 'claude') {
      const prepared = integrationManager.prepareClaudeTerminalAction(process.execPath, 'disconnect');
      const openError = await shell.openPath(prepared.commandPath);
      if (openError) throw new Error(`无法打开 Terminal 断开窗口：${openError}`);
      connectionHealth.clear(provider);
      emitConnectionHealth(provider);
      return {
        provider,
        state: 'terminal-opened',
        cliFound: true,
        installed: true,
        enabled: true,
        changed: false,
        restartRequired: true,
        operation: 'disconnect',
      };
    }

    const status = await integrationManager.inspect(provider);
    if (provider === 'codex' && status.state === 'cli-missing') {
      const prepared = integrationManager.prepare('codex');
      const installUrl = `codex://plugins/${PLUGIN_NAME}?marketplacePath=${encodeURIComponent(prepared.marketplacePath)}`;
      await shell.openExternal(installUrl);
      return {
        ...status,
        state: 'opened-disconnect',
        operation: 'disconnect',
        changed: false,
      };
    }

    const result = await integrationManager.uninstall(provider);
    connectionHealth.clear(provider);
    emitConnectionHealth(provider);
    return { ...result, operation: 'disconnect' };
  } catch (error) {
    reportRuntimeError(`${provider} disconnect`, error);
    throw error;
  }
}

async function inspectAgentIntegration(provider) {
  const result = await integrationManager.inspect(provider);
  if (result.state === 'error') reportRuntimeError(`${provider} connection check`, result.error || 'unknown error');
  const bundledVersion = integrationManager.getBundledVersion(provider);
  const updateAvailable = result.state === 'connected'
    && comparePluginVersions(result.version, bundledVersion) < 0;
  return connectionHealth.decorate(provider, { ...result, bundledVersion, updateAvailable });
}

async function testAgentIntegration(provider) {
  const status = await integrationManager.inspect(provider);
  const health = connectionHealth.snapshot(provider);
  if (status.state !== 'connected' && health.health !== 'active') {
    throw new Error('请先安装并启用状态插件');
  }
  return connectionHealth.decorate(provider, {
    ...status,
    ...connectionHealth.startTest(provider),
  });
}

if (hasSingleInstanceLock) app.on('second-instance', revealExistingInstance);

if (hasSingleInstanceLock) app.whenReady().then(() => {
  if (app.dock) app.dock.hide();
  configStore = new ConfigStore(app.getPath('userData'));
  config = configStore.load();
  if (configStore.loadWarning) reportRuntimeError('Settings', configStore.loadWarning);
  const activeCharacterId = loadConfiguredCharacter(config.pet.characterPackId);
  if (activeCharacterId !== config.pet.characterPackId) {
    config = { ...config, pet: { ...config.pet, characterPackId: activeCharacterId } };
  }
  const activeLanguageId = loadConfiguredLanguage(config.language.packId);
  if (activeLanguageId !== config.language.packId) {
    config = { ...config, language: { ...config.language, packId: activeLanguageId } };
  }
  if (config.startup.launchAtLogin) {
    try {
      syncLaunchAtLogin(true);
    } catch (error) {
      runtimeWarning = `无法同步登录启动设置：${error.message}`;
      reportRuntimeError('Launch at login', error);
    }
  }
  updateAgentState(currentAgentSnapshot);

  ipcMain.handle('character-pack:get', () => characterPack);
  ipcMain.handle('pet-config:get', () => ({ scale: config.pet.scale, ...getPetLayoutPayload() }));
  ipcMain.handle('agent-state:get', () => ({
    ...currentAgentSnapshot,
    motion: currentAgentSnapshot.activeCount > 0
      ? (currentAgentSnapshot.waitingCount === currentAgentSnapshot.activeCount ? 'waiting' : 'working')
      : (agentPaused ? 'idle' : 'roam'),
  }));
  ipcMain.handle('task-status:get', () => getVisibleTaskStatus());
  ipcMain.handle('settings:get', (event) => {
    assertSettingsSender(event);
    return getSettingsPayload();
  });
  ipcMain.handle('settings:save', (event, nextConfig) => {
    assertSettingsSender(event);
    try {
      const availableIds = new Set(listLanguagePacks().map((language) => language.id));
      if (!nextConfig || !availableIds.has(nextConfig.language?.packId)) {
        throw new Error('Selected language pack is not installed or is invalid');
      }
      const availableCharacterIds = new Set(listCharacterPacks().map((character) => character.id));
      if (!availableCharacterIds.has(nextConfig.pet?.characterPackId)) {
        throw new Error('Selected character pack is not installed or is invalid');
      }
      const saved = persistConfig(nextConfig);
      applyConfig(saved);
      return getSettingsPayload();
    } catch (error) {
      reportRuntimeError('Settings save', error);
      throw error;
    }
  });
  ipcMain.handle('settings:reset', (event) => {
    assertSettingsSender(event);
    try {
      const reset = persistConfig(DEFAULT_CONFIG);
      applyConfig(reset);
      return getSettingsPayload();
    } catch (error) {
      reportRuntimeError('Settings reset', error);
      throw error;
    }
  });
  ipcMain.handle('agent-integrations:inspect', async (event, provider) => {
    assertSettingsSender(event);
    try {
      return await inspectAgentIntegration(provider);
    } catch (error) {
      reportRuntimeError(`${provider} connection check`, error);
      throw error;
    }
  });
  ipcMain.handle('agent-integrations:install', async (event, provider) => {
    assertSettingsSender(event);
    return connectAgentIntegration(provider);
  });
  ipcMain.handle('agent-integrations:repair', async (event, provider) => {
    assertSettingsSender(event);
    return connectAgentIntegration(provider, true);
  });
  ipcMain.handle('agent-integrations:disconnect', async (event, provider) => {
    assertSettingsSender(event);
    return disconnectAgentIntegration(provider);
  });
  ipcMain.handle('agent-integrations:test', async (event, provider) => {
    assertSettingsSender(event);
    try {
      return await testAgentIntegration(provider);
    } catch (error) {
      reportRuntimeError(`${provider} connection test`, error);
      throw error;
    }
  });
  createApplicationMenu();
  createTray();
  createWindow();
  setupSystemMonitors();
  setupCalendarService();
  integrationManager = new IntegrationManager({
    resourcesRoot: getIntegrationResourcesRoot(),
    dataRoot: path.join(app.getPath('userData'), 'managed-integrations'),
  });
  setupAgentBridge();
  if (process.argv.includes('--settings')) createSettingsWindow();
});

app.on('window-all-closed', () => {
  if (allowImmediateQuit) app.quit();
});

app.on('before-quit', (event) => {
  if (!allowImmediateQuit && win && !win.isDestroyed()) {
    event.preventDefault();
    requestQuit();
    return;
  }
  clearTimeout(quitTimer);
  clearTimeout(idleChatterTimer);
  clearTimeout(contextMenuPauseTimer);
  clearInterval(batteryPollTimer);
  clearInterval(taskMaintenanceTimer);
  if (calendarService) calendarService.stop();
  if (agentBridge) agentBridge.stop();
  if (speechQueue) speechQueue.clear();
});
