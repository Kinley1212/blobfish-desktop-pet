const { app, BrowserWindow, screen, ipcMain, Tray, Menu, nativeImage, powerMonitor, shell, net } = require('electron');
const crypto = require('crypto');
const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');
const {
  shouldPauseAgentMovement,
  shouldPauseIdleSpeech,
  shouldPauseMovement,
} = require('./core/activity-gates');
const { AgentBridge } = require('./core/agent-bridge');
const { BatteryThresholdTracker, readMacBattery } = require('./core/battery-monitor');
const { CalendarService } = require('./core/calendar-service');
const { getNextAlarmOccurrence } = require('./core/clock-engine');
const { ClockService } = require('./core/clock-service');
const { ClockStore } = require('./core/clock-store');
const { ConnectionHealthTracker } = require('./core/connection-health');
const { ConfigStore, DEFAULT_CONFIG } = require('./core/config-store');
const { comparePluginVersions, IntegrationManager, PLUGIN_NAME } = require('./core/integration-manager');
const { loadCharacterPack } = require('./core/pack-loader');
const { loadAccessoryCatalog } = require('./core/accessory-loader');
const { loadDialoguePackSafe } = require('./core/dialogue-loader');
const { loadLanguagePack } = require('./core/language-pack-loader');
const {
  preparePetConfigForSave,
  repairLoadedPetConfigWithFallback,
} = require('./core/pet-config-geometry');
const {
  BUBBLE_STACK_RESERVE,
  PET_BOTTOM_MARGIN,
  PET_WINDOW_HEIGHT,
  PET_WINDOW_WIDTH,
  calculatePetMetrics,
  calculatePetRecoveryPlacement,
  calculateVerticalRoamPlacement,
  getMaxPetScale,
} = require('./core/pet-window-geometry');
const { PhraseEngine } = require('./core/phrase-engine');
const { ReminderScheduler, isInQuietHours } = require('./core/reminder-scheduler');
const {
  DEFAULT_NEEDS_INPUT_SOUND_ID,
  DEFAULT_TASK_COMPLETE_SOUND_ID,
  TASK_COMPLETE_SOUNDS,
  taskCompleteSoundPath,
} = require('./core/sound-catalog');
const { playTaskSoundFile } = require('./core/sound-player');
const { RuntimeErrorNotifier } = require('./core/runtime-error-notifier');
const { RuntimeWarningStore } = require('./core/runtime-warning-store');
const { SpeechQueue } = require('./core/speech-queue');
const { SPEECH_DURATION_MS } = require('./core/speech-timing');
const { StartupGreetingStore, getStartupGreeting } = require('./core/startup-greeting');
const { bindGracefulWindowClose, isLiveWindow } = require('./core/window-lifecycle');
const { formatProviderTaskSummary } = require('./core/task-menu-summary');
const { t: translateUi } = require('./core/ui-i18n');
const { advanceFractionalCoordinate, roundWindowCoordinate } = require('./core/fractional-position');
const { getCurrentTaskStatus, getTerminalTaskStatus } = require('./core/task-status-presenter');
const {
  readTaskLeases,
  readTaskLeasesAsync,
} = require('./core/task-lease-store');
const { TaskLeasePollEpoch } = require('./core/task-lease-poll-epoch');
const { getTaskSoundCue } = require('./core/task-transition-effects');
const { ProcessedAgentEvents, TaskTracker } = require('./core/task-tracker');
const {
  LATEST_RELEASE_URL,
  LATEST_MANIFEST_URL,
  buildGitHubUserAgent,
  buildMacInstallerScript,
  cleanupStaleUpdateStaging,
  getInstalledAppBundle,
  launchMacInstallerInBackground,
  resolveMacUpdateInstallTarget,
  selectManifestUpdate,
  selectReleaseUpdate,
  withUpdateTimeout,
} = require('./core/github-release-updater');
const { version: appVersion } = require('../package.json');

const userDataRoot = app.getPath('appData');
const appDisplayName = `水滴鱼Pro${appVersion}`;
const githubUserAgent = buildGitHubUserAgent(appVersion);
const isMacOS = process.platform === 'darwin';
app.setName(appDisplayName);
app.setPath('userData', path.join(userDataRoot, 'BlobfishDesktopPet'));
const hasSingleInstanceLock = app.requestSingleInstanceLock();

function uiLocale() {
  return config?.ui?.locale || DEFAULT_CONFIG.ui.locale;
}

function uiText(chinese, english, values) {
  return translateUi(uiLocale(), uiLocale() === 'en' ? english : chinese, values);
}
if (!hasSingleInstanceLock) app.quit();

const WINDOW_WIDTH = PET_WINDOW_WIDTH;
const WINDOW_HEIGHT = PET_WINDOW_HEIGHT;
const PET_WINDOW_GEOMETRY = Object.freeze({
  width: WINDOW_WIDTH,
  height: WINDOW_HEIGHT,
  bottomMargin: PET_BOTTOM_MARGIN,
});
const TICK_MS = 30;
const EXIT_ANIMATION_MS = 1700;
const DEFAULT_CHARACTER_PACK_ID = 'blobfish';
const DEFAULT_LANGUAGE_PACK_ID = 'blobfish-zh-TW';
const CHARACTERS_ROOT = path.join(__dirname, 'packs', 'characters');
const LANGUAGES_ROOT = path.join(__dirname, 'packs', 'languages');
const ACCESSORIES_ROOT = path.join(__dirname, 'packs', 'accessories');
// The wardrobe is static art, so it is read once and shared by every window.
const accessoryCatalog = loadAccessoryCatalog(ACCESSORIES_ROOT);
const DIALOGUES_ROOT = path.join(__dirname, 'packs', 'dialogues');
let dialoguePack = loadDialoguePackSafe(DIALOGUES_ROOT, DEFAULT_LANGUAGE_PACK_ID);
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
let petVisualTopOverflow = 0;
function getPetMetrics() {
  const metrics = calculatePetMetrics(
    characterPack.manifest.size,
    config.pet.scale,
    PET_WINDOW_GEOMETRY,
  );
  return Object.freeze({
    ...metrics,
    visualTopOverflow: Math.min(metrics.topMargin, Math.max(0, petVisualTopOverflow)),
  });
}

function getMinimumPetTopOffset(metrics) {
  return Math.min(
    metrics.topMargin,
    Math.max(0, Number(metrics.visualTopOverflow) || 0),
  );
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
let clockWin;
let dialogueWin;
let tray;
let direction = 1;
let verticalDirection = 1; // 1 = moving down, -1 = moving up (vertical roam mode)
let currentPetTopPrecise = null; // sub-pixel pet-top tracker for vertical roaming
let paused = false;
let contextMenuPaused = false;
let systemPaused = false;
let agentPaused = false;
let hoverPaused = false; // true while the cursor is resting on the pet
let currentX;
let currentY;
let petTopOffset = null;
let flingIntervalId = null;
let movementIntervalId = null;
let speechQueue;
let idleChatterTimer = null;
let chatInviteTimer = null;
let reminderTimer = null;
let displayRecoveryTimer = null;
const reminderScheduler = new ReminderScheduler();
let clickCount = 0;
let configStore;
let startupGreetingStore;
let clockStore;
let clockService;
let clockPropSpeechVisible = false;
let config = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
let phraseEngine = null;
const runtimeWarnings = new RuntimeWarningStore();
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
let taskLeasePollTimer = null;
let taskLeasePollInFlight = false;
let taskLeasePruneInFlight = false;
let taskLeaseDirectory = null;
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
const processedAgentEvents = new ProcessedAgentEvents();
const taskLeasePollEpoch = new TaskLeasePollEpoch();

const sessionStartedAt = Date.now();

function getDateContext(date = new Date()) {
  const hour = date.getHours();
  const weekday = date.getDay();
  return {
    hour,
    minute: date.getMinutes(),
    weekday,
    isLateNight: hour >= 23 || hour <= 4,
    isWeekend: weekday === 0 || weekday === 6,
    sessionHours: Math.floor((Date.now() - sessionStartedAt) / 3600000),
  };
}

// Picks a chatter line that fits the moment - deep night, a weekend, or a
// session that has been running for hours - and falls back to the generic
// line when the language pack has nothing for that situation.
function speakContextualIdleChatter(dateContext) {
  const options = { priority: SPEECH_PRIORITY.idle, durationMs: SPEECH_DURATION_MS.idleChatter };
  const candidates = [];
  if (dateContext.isLateNight) candidates.push('idle.lateNight');
  if (dateContext.isWeekend) candidates.push('idle.weekend');
  if (dateContext.sessionHours >= 4) candidates.push('idle.longSession');

  for (const event of candidates) {
    if (speak(event, dateContext, { ...options, replaceKey: event })) return true;
  }
  return speak('idle.chatter', dateContext, { ...options, replaceKey: 'idle.chatter' });
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
          characterPackIds: Array.isArray(pack.manifest.characterPackIds)
            ? [...pack.manifest.characterPackIds]
            : [],
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
          diy: pack.manifest.diy || null,
          maxScale: getMaxPetScale(pack.manifest.size, PET_WINDOW_GEOMETRY),
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
    runtimeWarnings.clear('character');
    return packId;
  } catch (error) {
    runtimeWarnings.set('character', `形象包 ${packId} 无法加载，已临时改用默认形象：${error.message}`);
    reportRuntimeError('Character pack', error);
    characterPack = loadCharacterPack(CHARACTERS_ROOT, DEFAULT_CHARACTER_PACK_ID);
    return DEFAULT_CHARACTER_PACK_ID;
  }
}

function loadConfiguredLanguage(packId) {
  try {
    const pack = loadLanguagePack(LANGUAGES_ROOT, packId);
    phraseEngine = new PhraseEngine(pack.phrases);
    runtimeWarnings.clear('language');
    return packId;
  } catch (error) {
    runtimeWarnings.set('language', `语言包 ${packId} 无法加载，已临时改用默认语言包：${error.message}`);
    reportRuntimeError('Language pack', error);
    const fallback = loadLanguagePack(LANGUAGES_ROOT, DEFAULT_LANGUAGE_PACK_ID);
    phraseEngine = new PhraseEngine(fallback.phrases);
    return DEFAULT_LANGUAGE_PACK_ID;
  }
}

function getEventCategory(event) {
  if (event.startsWith('schedule.')) return 'schedule';
  if (event.startsWith('startup.')) return 'system';
  if (event.startsWith('system.')) return 'system';
  if (event.startsWith('calendar.')) return 'calendar';
  if (event.startsWith('agent.')) return 'agents';
  if (event.startsWith('clock.')) return 'clock';
  return null;
}

function maybeSpeakStartupGreeting(date = new Date()) {
  if (!startupGreetingStore) return false;
  const greeting = getStartupGreeting(
    date,
    config.schedule,
    config.greetings,
    startupGreetingStore.get(),
  );
  if (!greeting) return false;

  const spoken = speak(greeting.event, greeting.context, {
    priority: SPEECH_PRIORITY.schedule,
    durationMs: SPEECH_DURATION_MS.idleChatter,
    replaceKey: 'startup.greeting',
  });
  if (!spoken) return false;

  try {
    startupGreetingStore.mark(greeting.dateKey);
    runtimeWarnings.clear('startupGreeting');
  } catch (error) {
    runtimeWarnings.set('startupGreeting', `无法记录今天的首次问候，下次启动可能会重复：${error.message}`);
    reportRuntimeError('Startup greeting state', error);
  }
  return true;
}

// Every so often the fish quietly offers to chat. It never steals focus: it
// just floats a bubble, and only if you click the fish does the window open.
const CHAT_INVITE_MIN_MS = 25 * 60 * 1000;
const CHAT_INVITE_MAX_MS = 55 * 60 * 1000;
const CHAT_INVITE_CHANCE = 0.5;
const CHAT_INVITE_LINES = ['……有空吗。', '陪我说会儿话？', '喂……在忙吗。', '有点无聊。要不聊聊？'];
const CHAT_INVITE_DURATION_MS = 9000;

function scheduleChatInvite() {
  clearTimeout(chatInviteTimer);
  const delay = CHAT_INVITE_MIN_MS + Math.random() * (CHAT_INVITE_MAX_MS - CHAT_INVITE_MIN_MS);
  chatInviteTimer = setTimeout(() => {
    maybeInviteToChat();
    scheduleChatInvite();
  }, delay);
}

function maybeInviteToChat() {
  if (!win || win.isDestroyed()) return;
  if (dialogueWin && !dialogueWin.isDestroyed()) return; // already chatting
  if (isIdleSpeechPaused() || flingIntervalId) return;
  if (isInQuietHours(new Date(), config.quietHours)) return;
  if (Math.random() >= CHAT_INVITE_CHANCE) return;

  const text = CHAT_INVITE_LINES[Math.floor(Math.random() * CHAT_INVITE_LINES.length)];
  win.webContents.send('chat-invite', { text, durationMs: CHAT_INVITE_DURATION_MS });
}

function isMovementPaused() {
  return shouldPauseMovement(getActivityGateState());
}

function isIdleSpeechPaused() {
  return shouldPauseIdleSpeech(getActivityGateState());
}

function getActivityGateState() {
  const allTasksWaiting = currentAgentSnapshot.activeCount > 0
    && currentAgentSnapshot.waitingCount === currentAgentSnapshot.activeCount;
  return {
    directlyPaused: paused,
    contextMenuPaused,
    systemPaused,
    agentMovementPaused: agentPaused,
    hoverPaused,
    allTasksWaiting,
  };
}

function isProviderEnabled(provider) {
  if (provider === 'codex') return config.integrations.codex;
  if (provider === 'claude' || provider === 'claude-code') return config.integrations.claudeCode;
  return false;
}

function setAgentIntegrationReceiving(provider, enabled) {
  if (provider !== 'codex' && provider !== 'claude') throw new Error('不支持的代理连接类型');
  const key = provider === 'codex' ? 'codex' : 'claudeCode';
  if (config.integrations[key] === enabled) return enabled;
  const saved = persistConfig({
    ...config,
    integrations: { ...config.integrations, [key]: enabled },
  });
  applyConfig(saved);
  return enabled;
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
  runtimeWarnings.clear('startup');
}

function requestQuit() {
  if (quitRequested) return;
  quitRequested = true;
  paused = true;
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

function setRoamWhenNoTasks(enabled) {
  if (config.pet.roamWhenNoTasks === enabled) return;
  const saved = persistConfig({
    ...config,
    pet: { ...config.pet, roamWhenNoTasks: enabled },
  });
  applyConfig(saved);
  speak(enabled ? 'interaction.idleRoamOn' : 'interaction.idleRoamOff', {}, {
    priority: SPEECH_PRIORITY.interaction,
    durationMs: 2800,
    replaceKey: 'interaction.idleRoamToggle',
    allowDuringQuiet: true,
  });
  if (settingsWin && !settingsWin.isDestroyed()) {
    settingsWin.webContents.send('setting-changed', {
      path: 'pet.roamWhenNoTasks',
      value: enabled,
    });
  }
}

function setRoamWhenTasks(enabled) {
  if (config.pet.roamWhenTasks === enabled) return;
  const saved = persistConfig({
    ...config,
    pet: { ...config.pet, roamWhenTasks: enabled },
  });
  applyConfig(saved);
  speak(enabled ? 'interaction.taskRoamOn' : 'interaction.taskRoamOff', {}, {
    priority: SPEECH_PRIORITY.interaction,
    durationMs: 2800,
    replaceKey: 'interaction.taskRoamToggle',
    allowDuringQuiet: true,
  });
  if (settingsWin && !settingsWin.isDestroyed()) {
    settingsWin.webContents.send('setting-changed', {
      path: 'pet.roamWhenTasks',
      value: enabled,
    });
  }
}

function formatClockDuration(milliseconds) {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  if (hours > 0) return `${hours}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

function runClockMenuAction(label, action) {
  try {
    action();
  } catch (error) {
    reportRuntimeError(label, error);
  }
}

function buildClockMenuItems() {
  if (!clockService) return [];
  const state = clockService.getState();
  const ringing = state.alerts.find((alert) => alert.state === 'ringing');
  const items = [];
  if (ringing) {
    items.push(
      {
        label: `${ringing.sourceType === 'alarm' ? '⏰' : '⏱'} ${ringing.label || uiText('时间到了', 'Time is up')}`,
        enabled: false,
      },
      {
        label: uiText('稍后 5 分钟', 'Snooze 5 minutes'),
        click: () => runClockMenuAction('Clock snooze', () => clockService.snoozeAlert(ringing.id, 5)),
      },
      {
        label: uiText('知道了', 'Dismiss'),
        click: () => runClockMenuAction('Clock dismiss', () => clockService.dismissAlert(ringing.id)),
      },
      { type: 'separator' },
    );
  }
  if (state.timer) {
    const remainingMs = state.timer.state === 'running'
      ? state.timer.dueAtMs - Date.now()
      : state.timer.remainingMs;
    items.push({
      label: `${uiText('计时器', 'Timer')} · ${formatClockDuration(remainingMs)}`,
      submenu: [
        {
          label: state.timer.state === 'running'
            ? uiText('暂停计时', 'Pause timer')
            : uiText('继续计时', 'Resume timer'),
          click: () => runClockMenuAction(
            state.timer.state === 'running' ? 'Pause timer' : 'Resume timer',
            () => (state.timer.state === 'running' ? clockService.pauseTimer() : clockService.resumeTimer()),
          ),
        },
        {
          label: uiText('增加 5 分钟', 'Add 5 minutes'),
          click: () => runClockMenuAction('Extend timer', () => clockService.extendTimer(5)),
        },
        {
          label: uiText('取消计时', 'Cancel timer'),
          click: () => runClockMenuAction('Cancel timer', () => clockService.cancelTimer()),
        },
      ],
    });
  } else {
    items.push({
      label: uiText('快速计时', 'Quick timer'),
      submenu: [5, 15, 25, 45].map((minutes) => ({
        label: minutes === 25
          ? uiText('25 分钟专注', '25-minute focus')
          : uiText(`${minutes} 分钟`, `${minutes} minutes`),
        click: () => runClockMenuAction(
          'Start timer',
          () => clockService.startTimer({
            durationMinutes: minutes,
            label: minutes === 25 ? uiText('专注', 'Focus') : '',
          }),
        ),
      })),
    });
  }
  items.push({ label: uiText('闹钟与计时器…', 'Alarms & timers…'), click: () => createClockWindow() });
  return items;
}

function buildPetMenuTemplate() {
  const tasks = taskTracker ? taskTracker.getTasks() : [];
  return [
    { label: uiText('任务状态', 'Task status'), enabled: false },
    {
      label: formatProviderTaskSummary(tasks, 'codex', 'Codex', config.integrations.codex, uiLocale()),
      enabled: false,
    },
    {
      label: formatProviderTaskSummary(tasks, 'claude-code', 'Claude', config.integrations.claudeCode, uiLocale()),
      enabled: false,
    },
    { type: 'separator' },
    ...buildClockMenuItems(),
    { type: 'separator' },
    { label: uiText('找水滴鱼聊天…', 'Chat with the pet…'), click: () => createDialogueWindow() },
    { label: uiText('打开设置…', 'Open settings…'), click: () => createSettingsWindow() },
    {
      label: uiText('任务进行时游动', 'Move while tasks are running'),
      type: 'checkbox',
      checked: config.pet.roamWhenTasks,
      click: (item) => {
        try {
          setRoamWhenTasks(item.checked);
        } catch (error) {
          reportRuntimeError('Task roaming setting', error);
          rebuildTrayMenu();
        }
      },
    },
    {
      label: uiLocale() === 'en'
        ? uiText('没有任务时也继续游动', 'Keep moving without tasks')
        : (characterPack?.settingsCopy?.roamWithoutTasksLabel || '没有任务时也继续游动'),
      type: 'checkbox',
      checked: config.pet.roamWhenNoTasks,
      click: (item) => {
        try {
          setRoamWhenNoTasks(item.checked);
        } catch (error) {
          reportRuntimeError('Idle roaming setting', error);
          rebuildTrayMenu();
        }
      },
    },
    {
      label: uiText('登录后自动启动', 'Open at login'),
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
    { label: uiText(`退出${appDisplayName}`, `Quit ${appDisplayName}`), click: () => requestQuit() },
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
        { label: uiText('设置…', 'Settings…'), accelerator: 'CmdOrCtrl+,', click: () => createSettingsWindow() },
        { label: uiText('闹钟与计时器…', 'Alarms & timers…'), accelerator: 'CmdOrCtrl+Shift+T', click: () => createClockWindow() },
        { type: 'separator' },
        { label: uiText(`退出${appDisplayName}`, `Quit ${appDisplayName}`), accelerator: 'CmdOrCtrl+Q', click: () => requestQuit() },
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
    width: 920,
    height: 720,
    minWidth: 720,
    minHeight: 560,
    title: uiText('水滴鱼设置', 'Blobfish Settings'),
    backgroundColor: '#eef1ef',
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

function createClockWindow() {
  if (clockWin && !clockWin.isDestroyed()) {
    clockWin.show();
    clockWin.focus();
    return;
  }

  clockWin = new BrowserWindow({
    width: 460,
    height: 700,
    minWidth: 420,
    minHeight: 560,
    title: uiText('闹钟与计时器', 'Alarms & Timers'),
    backgroundColor: '#eef3f1',
    webPreferences: {
      preload: path.join(__dirname, 'clock-preload.js'),
      contextIsolation: true,
      sandbox: true,
    },
  });
  clockWin.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  clockWin.on('closed', () => { clockWin = null; });
  clockWin.loadFile(path.join(__dirname, 'clock.html'));
}

// The chooser lives in its own small window rather than the click-through pet
// window, so its buttons are always reliably clickable.
function createDialogueWindow() {
  if (dialogueWin && !dialogueWin.isDestroyed()) {
    dialogueWin.show();
    dialogueWin.focus();
    return;
  }
  dialogueWin = new BrowserWindow({
    width: 320,
    height: 340,
    resizable: false,
    fullscreenable: false,
    title: uiText('和水滴鱼聊天', 'Chat with your pet'),
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    alwaysOnTop: true,
    webPreferences: {
      preload: path.join(__dirname, 'dialogue-preload.js'),
      contextIsolation: true,
      sandbox: true,
    },
  });
  dialogueWin.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  dialogueWin.on('closed', () => { dialogueWin = null; });
  dialogueWin.loadFile(path.join(__dirname, 'dialogue.html'));
}

function assertDialogueSender(event) {
  return dialogueWin && !dialogueWin.isDestroyed() && event.sender.id === dialogueWin.webContents.id;
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

function assertClockSender(event) {
  if (!clockWin || clockWin.isDestroyed() || event.sender.id !== clockWin.webContents.id) {
    throw new Error('Clock request came from an untrusted window');
  }
}

function assertPetSender(event) {
  if (!win || win.isDestroyed() || event.sender.id !== win.webContents.id) {
    throw new Error('Pet request came from an untrusted window');
  }
}

function getSettingsPayload() {
  return {
    appVersion,
    config: JSON.parse(JSON.stringify(config)),
    characters: listCharacterPacks(),
    languages: listLanguagePacks(),
    accessories: accessoryCatalog,
    taskCompleteSounds: TASK_COMPLETE_SOUNDS.map((sound) => ({ id: sound.id, label: sound.label })),
    warning: runtimeWarnings.getMessage(configStore.loadWarning),
    integrationStatus: { calendar: calendarStatus, agentBridge: agentBridgeStatus },
  };
}

function getClockWindowPayload(state = clockService?.getState()) {
  return {
    state: state || null,
    uiLocale: uiLocale(),
    sounds: TASK_COMPLETE_SOUNDS.map((sound) => ({ id: sound.id, label: sound.label })),
    workdays: [...config.schedule.workdays],
  };
}

function getClockSummaryPayload(state = clockService?.getState(), nowMs = Date.now()) {
  if (!state) return { timer: null, nextAlarm: null, alerts: [], hasEnabledAlarm: false };
  let nextAlarm = null;
  for (const alarm of state.alarms) {
    const occurrence = getNextAlarmOccurrence(alarm, nowMs, config.schedule.workdays);
    if (!occurrence || (nextAlarm && nextAlarm.dueAtMs <= occurrence.dueAtMs)) continue;
    nextAlarm = {
      id: alarm.id,
      label: alarm.label,
      dueAtMs: occurrence.dueAtMs,
      time: alarm.time,
    };
  }
  return {
    timer: state.timer ? { ...state.timer } : null,
    nextAlarm,
    alerts: state.alerts
      .filter((alert) => alert.state === 'ringing')
      .map((alert) => ({ ...alert })),
    // A snoozed one-shot alert still belongs in the pet's hand even though
    // its source alarm has already disabled itself.
    hasEnabledAlarm: state.alarms.some((alarm) => alarm.enabled)
      || state.alerts.some((alert) => alert.sourceType === 'alarm'),
  };
}

function hasVisibleAlarmProp(state) {
  return Boolean(state)
    && (
      state.alarms.some((alarm) => alarm.enabled)
      || state.alerts.some((alert) => alert.sourceType === 'alarm')
    );
}

function clockMenuSignature(state) {
  return JSON.stringify({
    timer: state.timer && {
      id: state.timer.id,
      state: state.timer.state,
      dueAtMs: state.timer.dueAtMs,
      remainingMs: state.timer.remainingMs,
    },
    alerts: state.alerts.map((alert) => [alert.id, alert.state, alert.dueAtMs]),
    alarms: state.alarms.map((alarm) => [alarm.id, alarm.enabled, alarm.time, alarm.mode]),
  });
}

function broadcastClockState(state) {
  if (clockWin && !clockWin.isDestroyed()) {
    clockWin.webContents.send('clock-state', getClockWindowPayload(state));
  }
  if (win && !win.isDestroyed()) {
    win.webContents.send('clock-state', getClockSummaryPayload(state));
  }
  const signature = clockMenuSignature(state);
  if (signature !== broadcastClockState.lastMenuSignature) {
    broadcastClockState.lastMenuSignature = signature;
    rebuildTrayMenu();
  }
}

function handleClockStateChange(state, details = {}) {
  broadcastClockState(state);
  const nextPropVisible = hasVisibleAlarmProp(state);
  const propChanged = nextPropVisible !== clockPropSpeechVisible;
  clockPropSpeechVisible = nextPropVisible;
  if (details.reason === 'reconcile' || details.reason === 'preferences-updated') return;

  if (propChanged) {
    speak(
      nextPropVisible ? 'clock.alarmClockAppeared' : 'clock.alarmClockDisappeared',
      {},
      {
        priority: SPEECH_PRIORITY.schedule,
        durationMs: 5000,
        replaceKey: 'clock.prop',
      },
    );
    return;
  }

  const eventByReason = {
    'timer-started': 'clock.timerStarted',
    'timer-paused': 'clock.timerPaused',
    'timer-resumed': 'clock.timerResumed',
    'timer-extended': 'clock.timerExtended',
    'timer-cancelled': 'clock.timerCancelled',
    'alert-snoozed': 'clock.alertSnoozed',
    'alert-dismissed': 'clock.alertDismissed',
  };
  const event = eventByReason[details.reason];
  if (!event) return;
  speak(event, { minutes: details.minutes }, {
    priority: SPEECH_PRIORITY.schedule,
    durationMs: 4600,
    replaceKey: 'clock.control',
  });
}

function playClockAlertSound(alerts) {
  if (!alerts.length || !clockService) return;
  const state = clockService.getState();
  const containsAlarm = alerts.some((alert) => alert.sourceType === 'alarm');
  const setting = containsAlarm ? state.preferences.alarmSound : state.preferences.timerSound;
  if (!setting.enabled) return;
  if (
    !state.preferences.allowSoundDuringQuietHours
    && isInQuietHours(new Date(), config.quietHours)
  ) return;
  const soundPath = taskCompleteSoundPath(setting.soundId);
  if (!soundPath) return;
  playTaskSoundFile(soundPath, {
    execFile,
    beep: () => shell.beep(),
    onError: (error) => reportRuntimeError('Clock alert sound', error),
  });
}

function handleClockDue(alerts) {
  playClockAlertSound(alerts);
  const first = alerts[0];
  const context = {
    label: first?.label || undefined,
    count: alerts.length,
  };
  speak(first?.sourceType === 'alarm' ? 'clock.alarmRinging' : 'clock.timerCompleted', context, {
    priority: SPEECH_PRIORITY.urgent,
    durationMs: 7000,
    replaceKey: 'clock.ringing',
    allowDuringQuiet: true,
    action: 'attention',
  });
}

function handleClockMissed(items) {
  const first = items[0];
  speak('clock.missedAfterWake', {
    label: first?.label || undefined,
    count: items.length,
  }, {
    priority: SPEECH_PRIORITY.schedule,
    durationMs: 6000,
    replaceKey: 'clock.missed',
  });
}

function setupClockService() {
  clockStore = new ClockStore(app.getPath('userData'));
  clockStore.load();
  const loadWarning = clockStore.loadWarning;
  clockService = new ClockService(clockStore, {
    getWorkdays: () => [...config.schedule.workdays],
    onChange: (state, details) => handleClockStateChange(state, details),
    onDue: handleClockDue,
    onMissed: handleClockMissed,
  });
  clockPropSpeechVisible = hasVisibleAlarmProp(clockService.getState());
  clockService.start();
  if (loadWarning) {
    runtimeWarnings.set('clock', loadWarning);
    reportRuntimeError('Clock state', loadWarning);
  }
}

function sendAppUpdateProgress(payload) {
  if (settingsWin && !settingsWin.isDestroyed()) {
    settingsWin.webContents.send('app-update-progress', payload);
  }
}

async function checkForAppUpdate() {
  if (!app.isPackaged) {
    return { state: 'development', currentVersion: appVersion, message: '开发模式不检查安装包更新。' };
  }
  if (!isMacOS || !['arm64', 'x64'].includes(process.arch)) {
    return { state: 'unsupported', currentVersion: appVersion, message: '当前版本暂时只支持 macOS 自动安装更新。' };
  }

  try {
    const manifestResult = await withUpdateTimeout('检查 GitHub 更新', 15 * 1000, async (signal) => {
      const response = await net.fetch(LATEST_MANIFEST_URL, {
        headers: { 'User-Agent': githubUserAgent },
        signal,
      });
      return {
        ok: response.ok,
        status: response.status,
        manifest: response.ok ? await response.json() : null,
      };
    });
    if (manifestResult.ok) {
      return selectManifestUpdate(manifestResult.manifest, {
        currentVersion: appVersion,
        architecture: process.arch,
      });
    }
    if (manifestResult.status !== 404) {
      console.warn(`Cannot read GitHub update manifest: ${manifestResult.status}`);
    }

    const releaseResult = await withUpdateTimeout('检查 GitHub 更新', 15 * 1000, async (signal) => {
      const response = await net.fetch(LATEST_RELEASE_URL, {
        headers: {
          Accept: 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': githubUserAgent,
        },
        signal,
      });
      return {
        ok: response.ok,
        status: response.status,
        release: response.ok ? await response.json() : null,
      };
    });
    if (releaseResult.status === 404) {
      return {
        state: 'no-release',
        currentVersion: appVersion,
        message: 'GitHub 还没有发布正式 Release；PR、分支和 Draft 不会被一键更新发现。',
      };
    }
    if (!releaseResult.ok) throw new Error(`GitHub 返回了 ${releaseResult.status}`);
    return selectReleaseUpdate(releaseResult.release, {
      currentVersion: appVersion,
      architecture: process.arch,
    });
  } catch (error) {
    console.warn(`Cannot check GitHub release update: ${error.message}`);
    return { state: 'error', currentVersion: appVersion, message: `无法检查 GitHub 更新：${error.message}` };
  }
}

async function writeAll(fileHandle, value) {
  const buffer = Buffer.from(value);
  let offset = 0;
  while (offset < buffer.length) {
    const { bytesWritten } = await fileHandle.write(buffer, offset, buffer.length - offset, null);
    if (bytesWritten <= 0) throw new Error('无法写入更新文件');
    offset += bytesWritten;
  }
}

async function downloadReleaseAsset(update, destination, progressDetails = {}) {
  return withUpdateTimeout('下载更新包', 10 * 60 * 1000, async (signal) => {
    const response = await net.fetch(update.asset.url, {
      headers: { 'User-Agent': githubUserAgent },
      signal,
    });
    if (!response.ok || !response.body) throw new Error(`GitHub 安装包下载失败（${response.status}）`);

    const fileHandle = await fs.promises.open(destination, 'wx', 0o600);
    const checksum = crypto.createHash('sha256');
    const reader = response.body.getReader();
    let received = 0;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        if (!value || value.length === 0) continue;
        received += value.length;
        if (received > update.asset.size) throw new Error('下载文件超过 GitHub 声明的大小，已停止更新');
        checksum.update(value);
        await writeAll(fileHandle, value);
        sendAppUpdateProgress({
          state: 'downloading',
          version: update.version,
          received,
          total: update.asset.size,
          ...progressDetails,
        });
      }
    } finally {
      await fileHandle.close();
    }
    if (received !== update.asset.size) throw new Error('下载文件大小与 GitHub 声明不一致，已停止更新');
    if (checksum.digest('hex') !== update.asset.digest) throw new Error('下载文件校验失败，已停止更新');
  });
}

function getUpdateStagingDirectory() {
  const updateRoot = path.join(app.getPath('userData'), 'updates');
  fs.mkdirSync(updateRoot, { recursive: true, mode: 0o700 });
  const cleanup = cleanupStaleUpdateStaging(updateRoot);
  if (cleanup.failed.length > 0) {
    console.warn(`Could not clean ${cleanup.failed.length} stale update staging director${cleanup.failed.length === 1 ? 'y' : 'ies'}`);
  }
  return fs.mkdtempSync(path.join(updateRoot, 'release-'));
}

async function installGithubUpdate() {
  const update = await checkForAppUpdate();
  if (update.state !== 'available') {
    throw new Error(update.message || '没有可安装的新版本');
  }
  if (!app.isPackaged) throw new Error('开发模式不能安装更新');

  const currentAppPath = getInstalledAppBundle(process.execPath);
  const installPlan = resolveMacUpdateInstallTarget({
    currentAppPath,
    bundleName: update.asset.bundleName,
    userApplicationsDirectory: path.join(app.getPath('home'), 'Applications'),
  });
  const { targetAppPath } = installPlan;
  if (fs.existsSync(targetAppPath)) {
    const locationLabel = installPlan.installLocation === 'user-applications'
      ? '个人“应用程序”文件夹'
      : '当前文件夹';
    throw new Error(`Pro${update.version} 已经在${locationLabel}里，请直接打开它`);
  }

  const stagingDirectory = getUpdateStagingDirectory();
  const zipPath = path.join(stagingDirectory, update.asset.name);
  const commandPath = path.join(stagingDirectory, '安装水滴鱼更新.command');
  try {
    const progressDetails = { installLocation: installPlan.installLocation };
    sendAppUpdateProgress({
      state: 'preparing',
      version: update.version,
      ...progressDetails,
    });
    sendAppUpdateProgress({
      state: 'downloading',
      version: update.version,
      received: 0,
      total: update.asset.size,
      ...progressDetails,
    });
    await downloadReleaseAsset(update, zipPath, progressDetails);
    sendAppUpdateProgress({ state: 'installing', version: update.version, ...progressDetails });
    fs.writeFileSync(commandPath, buildMacInstallerScript({
      currentAppPath,
      targetAppPath,
      zipPath,
      stagingDirectory,
      processId: process.pid,
      removeOldApp: installPlan.removeOldApp,
    }), { mode: 0o700 });
    fs.chmodSync(commandPath, 0o700);
    await launchMacInstallerInBackground(commandPath);
  } catch (error) {
    fs.rmSync(stagingDirectory, { recursive: true, force: true });
    throw error;
  }

  setTimeout(() => {
    allowImmediateQuit = true;
    app.quit();
  }, 500);
  return {
    state: 'installing',
    version: update.version,
    installLocation: installPlan.installLocation,
  };
}

function getIntegrationResourcesRoot() {
  if (app.isPackaged) return path.join(process.resourcesPath, 'integrations');
  return path.join(__dirname, '..', 'integrations');
}

function getAgentEventSenderPath() {
  if (app.isPackaged) return path.join(process.resourcesPath, 'native', 'blobfish-agent-event-sender');
  return path.join(__dirname, '..', 'native', 'build', process.arch, 'blobfish-agent-event-sender');
}

function applyConfig(nextConfig) {
  const codexWasEnabled = config.integrations.codex;
  const claudeWasEnabled = config.integrations.claudeCode;
  const uiLocaleChanged = nextConfig.ui.locale !== config.ui.locale;
  const agentProviderConfigChanged = (
    codexWasEnabled !== nextConfig.integrations.codex
    || claudeWasEnabled !== nextConfig.integrations.claudeCode
  );
  if (agentProviderConfigChanged) taskLeasePollEpoch.invalidate();
  const characterChanged = nextConfig.pet.characterPackId !== config.pet.characterPackId;
  const sizeChanged = characterChanged || nextConfig.pet.scale !== config.pet.scale;
  const languageChanged = !phraseEngine || nextConfig.language.packId !== config.language.packId;
  let previousPetPosition = null;
  if (sizeChanged && win && !win.isDestroyed()) {
    const [x, y] = win.getPosition();
    const oldMetrics = getPetMetrics();
    const oldTopOffset = Number.isFinite(petTopOffset) ? petTopOffset : oldMetrics.topMargin;
    previousPetPosition = {
      x,
      visibleTop: y + oldTopOffset - oldMetrics.visualTopOverflow,
      topOffset: oldTopOffset,
      visualTopOverflow: oldMetrics.visualTopOverflow,
    };
  }
  if (characterChanged) petVisualTopOverflow = 0;
  config = nextConfig;
  if (codexWasEnabled && !config.integrations.codex) {
    connectionHealth.clear('codex');
    emitConnectionHealth('codex');
  }
  if (claudeWasEnabled && !config.integrations.claudeCode) {
    connectionHealth.clear('claude');
    emitConnectionHealth('claude');
  }
  if (characterChanged) loadConfiguredCharacter(config.pet.characterPackId);
  if (languageChanged) {
    loadConfiguredLanguage(config.language.packId);
    dialoguePack = loadDialoguePackSafe(DIALOGUES_ROOT, config.language.packId);
  }
  if (calendarService) calendarService.setEnabled(config.integrations.calendar);
  if (taskTracker) {
    if (!config.integrations.codex) taskTracker.removeProvider('codex');
    if (!config.integrations.claudeCode) taskTracker.removeProvider('claude-code');
    const reenabledProviders = [];
    if (!codexWasEnabled && config.integrations.codex) reenabledProviders.push('codex');
    if (!claudeWasEnabled && config.integrations.claudeCode) reenabledProviders.push('claude-code');
    if (reenabledProviders.length > 0) {
      for (const provider of reenabledProviders) processedAgentEvents.forgetProvider(provider);
      try {
        recoverTaskLeases(
          path.join(app.getPath('userData'), 'agent-task-leases'),
          new Set(reenabledProviders),
        );
      } catch (error) {
        reportRuntimeError('Task lease recovery', error);
      }
    }
    updateAgentState(taskTracker.snapshot());
    emitTaskStatus();
  }
  if (win && !win.isDestroyed()) {
    if (previousPetPosition) {
      const metrics = getPetMetrics();
      const nextTopOffset = Math.min(
        metrics.topMargin,
        Math.max(
          getMinimumPetTopOffset(metrics),
          previousPetPosition.topOffset
            + metrics.visualTopOverflow
            - previousPetPosition.visualTopOverflow,
        ),
      );
      const nextPetTop = previousPetPosition.visibleTop + metrics.visualTopOverflow;
      applyProjectedPetPlacement(projectPetWindowPosition(
        previousPetPosition.x,
        nextPetTop - nextTopOffset,
        nextTopOffset,
        metrics,
      ));
    }
    if (characterChanged) win.webContents.send('character-pack', getCharacterPayload());
    win.webContents.send('pet-config', getPetConfigPayload());
    syncHoverState();
  }
  scheduleIdleChatter();
  scheduleChatInvite();
  scheduleReminders();
  rebuildTrayMenu();
  if (uiLocaleChanged) createApplicationMenu();
}

function persistConfig(nextConfig, characterSize = characterPack.manifest.size) {
  // Geometry validation is deliberately completed before login-item changes
  // or any disk write, so a character/scale mismatch cannot partially save.
  const validated = preparePetConfigForSave(nextConfig, characterSize, PET_WINDOW_GEOMETRY);
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

function getCharacterDiy(packId) {
  return config.pet.customization[packId] || null;
}

function getCharacterAccessories(packId) {
  return config.pet.accessories[packId] || null;
}

function getCharacterPayload() {
  return { ...characterPack, accessories: accessoryCatalog };
}

function getPetConfigPayload() {
  return {
    uiLocale: uiLocale(),
    scale: config.pet.scale,
    customization: getCharacterDiy(config.pet.characterPackId),
    accessories: getCharacterAccessories(config.pet.characterPackId),
    ...getPetLayoutPayload(),
  };
}

function getPetLayoutPayload() {
  const metrics = getPetMetrics();
  const rawTopOffset = Number.isFinite(petTopOffset) ? petTopOffset : metrics.topMargin;
  const topOffset = Math.min(
    metrics.topMargin,
    Math.max(getMinimumPetTopOffset(metrics), rawTopOffset),
  );
  return {
    topOffset,
    bubblePlacement: topOffset - metrics.visualTopOverflow < BUBBLE_STACK_RESERVE
      ? 'below'
      : 'above',
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

function getAvailableWorkAreas() {
  const workAreas = screen.getAllDisplays()
    .map((display) => display.workArea)
    .filter(isSaneRect);
  if (workAreas.length > 0) return workAreas;

  const primary = screen.getPrimaryDisplay()?.workArea;
  return isSaneRect(primary) ? [primary] : [];
}

function projectPetWindowPosition(
  windowX,
  windowY,
  topOffset,
  metrics = getPetMetrics(),
  workAreas = getAvailableWorkAreas(),
) {
  if (workAreas.length === 0) return null;
  return calculatePetRecoveryPlacement({
    x: windowX,
    y: windowY,
    petTopOffset: topOffset,
  }, metrics, workAreas);
}

function applyProjectedPetPlacement(placement) {
  if (!placement) return false;
  petTopOffset = placement.topOffset;
  currentPetTopPrecise = placement.petTop;
  currentX = placement.windowX;
  currentY = roundWindowCoordinate(placement.windowY);
  safeSetPosition(placement.windowX, placement.windowY);
  syncPetLayout();
  return true;
}

function applyReportedPetVisualBounds(payload) {
  const reportedOverflow = payload?.topOverflow;
  if (
    typeof reportedOverflow !== 'number'
    || !Number.isFinite(reportedOverflow)
    || reportedOverflow < 0
  ) return false;

  const baseMetrics = calculatePetMetrics(
    characterPack.manifest.size,
    config.pet.scale,
    PET_WINDOW_GEOMETRY,
  );
  const nextOverflow = Math.min(baseMetrics.topMargin, reportedOverflow);
  if (Math.abs(nextOverflow - petVisualTopOverflow) < 0.25) return false;

  if (!win || win.isDestroyed()) {
    petVisualTopOverflow = nextOverflow;
    return true;
  }

  const workAreas = getAvailableWorkAreas();
  const [windowX, windowY] = win.getPosition();
  const oldMetrics = getPetMetrics();
  const oldTopOffset = Number.isFinite(petTopOffset) ? petTopOffset : oldMetrics.topMargin;
  const oldPetTop = windowY + oldTopOffset;
  const oldVisibleTop = oldPetTop - oldMetrics.visualTopOverflow;
  const petCenterX = windowX + oldMetrics.offsetX + oldMetrics.width / 2;
  const wasAnchoredAtTop = workAreas.some((area) => (
    petCenterX >= area.x
    && petCenterX < area.x + area.width
    && Math.abs(oldVisibleTop - area.y) <= 1.5
  ));

  petVisualTopOverflow = nextOverflow;
  const metrics = getPetMetrics();
  const nextTopOffset = wasAnchoredAtTop
    ? oldTopOffset + nextOverflow - oldMetrics.visualTopOverflow
    : oldTopOffset;
  const placement = projectPetWindowPosition(
    windowX,
    windowY,
    nextTopOffset,
    metrics,
    workAreas,
  );
  applyProjectedPetPlacement(placement);
  syncPetLayout(true);
  return true;
}

function recoverPetAfterDisplayChange() {
  displayRecoveryTimer = null;
  if (!win || win.isDestroyed()) return;

  const workAreas = getAvailableWorkAreas();
  if (workAreas.length === 0) return;

  const [windowX, windowY] = win.getPosition();
  const metrics = getPetMetrics();
  const placement = calculatePetRecoveryPlacement({
    x: windowX,
    y: windowY,
    petTopOffset: Number.isFinite(petTopOffset) ? petTopOffset : metrics.topMargin,
  }, metrics, workAreas);

  if (flingIntervalId) {
    clearInterval(flingIntervalId);
    flingIntervalId = null;
    paused = false;
  }

  applyProjectedPetPlacement(placement);
  syncPetLayout(true);
  syncHoverState();
}

function scheduleDisplayRecovery() {
  clearTimeout(displayRecoveryTimer);
  // macOS can emit several topology and work-area events during one display
  // transition. Wait for that short burst to settle before choosing a target.
  displayRecoveryTimer = setTimeout(recoverPetAfterDisplayChange, 80);
}

function setupDisplayMonitors() {
  screen.on('display-added', scheduleDisplayRecovery);
  screen.on('display-removed', scheduleDisplayRecovery);
  screen.on('display-metrics-changed', scheduleDisplayRecovery);
}

function stopPetMotionTimers() {
  clearInterval(movementIntervalId);
  clearInterval(flingIntervalId);
  movementIntervalId = null;
  flingIntervalId = null;
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
    minimizable: false,
    movable: false,
    skipTaskbar: true,
    hasShadow: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      sandbox: true,
    },
  });

  const petWindow = win;
  bindGracefulWindowClose(petWindow, {
    canCloseImmediately: () => allowImmediateQuit,
    requestQuit,
    onClosed: () => {
      stopPetMotionTimers();
      if (win === petWindow) win = null;
      if (!allowImmediateQuit && !quitRequested) requestQuit();
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

  ipcMain.on('hover-pause', (_event, value) => {
    hoverPaused = Boolean(value);
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

  ipcMain.on('pet-stroked', (_event, streak) => {
    // The blush is handled locally in the renderer; here we just voice the
    // reaction through the phrase engine so it honors the active language pack.
    // Keep stroking without pausing and the reaction escalates: a longer
    // streak reaches for warmer lines, falling back to the plain ones when a
    // language pack doesn't define them.
    const count = Number.isFinite(streak) ? streak : 1;
    const options = {
      priority: SPEECH_PRIORITY.interaction,
      durationMs: 2600,
      allowDuringQuiet: true,
    };
    const candidates = [];
    if (count >= 6) candidates.push('interaction.pettingLots');
    if (count >= 3) candidates.push('interaction.pettingMore');
    candidates.push('interaction.petting');

    for (const event of candidates) {
      if (speak(event, { count }, { ...options, replaceKey: event })) break;
    }
  });

  ipcMain.on('pet-context-menu', showPetContextMenu);
  ipcMain.on('pet-open-chat', () => createDialogueWindow());
  ipcMain.on('pet-visual-bounds', (event, payload) => {
    assertPetSender(event);
    applyReportedPetVisualBounds(payload);
  });
  ipcMain.handle('dialogue:get', (event) => (assertDialogueSender(event) ? dialoguePack : null));
  ipcMain.handle('dialogue:character', (event) => {
    if (!assertDialogueSender(event)) return null;
    return {
      manifest: characterPack.manifest,
      uiLocale: uiLocale(),
      svg: characterPack.svg,
      accessories: accessoryCatalog,
      worn: getCharacterAccessories(config.pet.characterPackId),
      customization: getCharacterDiy(config.pet.characterPackId),
    };
  });
  ipcMain.on('dialogue:react', (event, reaction) => {
    if (!assertDialogueSender(event)) return;
    if (!reaction || typeof reaction !== 'object') return;
    const text = typeof reaction.reply === 'string' ? reaction.reply.slice(0, 200) : '';
    const face = typeof reaction.face === 'string' ? reaction.face : null;
    if (!win || win.isDestroyed()) return;
    // Reuse the pet's own bubble + expression so the reaction shows on the
    // desktop, not in the chat window.
    win.webContents.send('dialogue-reaction', { text, face, durationMs: 3200 });
  });
  ipcMain.on('dialogue:close', (event) => {
    if (assertDialogueSender(event)) dialogueWin.close();
  });

  ipcMain.on('drag-start', () => {
    paused = true;
    currentX = win ? win.getPosition()[0] : currentX;
  });

  ipcMain.on('drag-move', (_event, dx, dy) => {
    if (!win || !Number.isFinite(dx) || !Number.isFinite(dy)) return;
    const [x, y] = win.getPosition();
    const petMetrics = getPetMetrics();
    const currentTopOffset = Number.isFinite(petTopOffset) ? petTopOffset : petMetrics.topMargin;
    const placement = projectPetWindowPosition(
      x + dx,
      y + dy,
      currentTopOffset,
      petMetrics,
    );
    applyProjectedPetPlacement(placement);
  });

  ipcMain.on('drag-end', (_event, vxPerMs, vyPerMs) => {
    if (!win) return;

    let vx = (vxPerMs || 0) * TICK_MS * THROW_POWER;
    let vy = (vyPerMs || 0) * TICK_MS * THROW_POWER;
    const speed = Math.hypot(vx, vy);

    if (!Number.isFinite(speed) || speed < FLING_MIN_SPEED) {
      const [x, y] = win.getPosition();
      const metrics = getPetMetrics();
      applyProjectedPetPlacement(projectPetWindowPosition(
        x,
        y,
        Number.isFinite(petTopOffset) ? petTopOffset : metrics.topMargin,
        metrics,
      ));
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

  movementIntervalId = setInterval(() => {
    if (isMovementPaused() || flingIntervalId || !isLiveWindow(win)) return;
    const [wx, wy] = win.getPosition();
    const petMetrics = getPetMetrics();
    const nativePetTop = wy + (Number.isFinite(petTopOffset) ? petTopOffset : petMetrics.topMargin);
    const workAreas = getAvailableWorkAreas();
    if (workAreas.length === 0) return;

    if (config.pet.moveAxis === 'vertical') {
      let nearestBounds = screen.getDisplayNearestPoint({
        x: wx + petMetrics.offsetX + petMetrics.width / 2,
        y: nativePetTop + petMetrics.height / 2,
      }).workArea;
      if (!isSaneRect(nearestBounds)) {
        nearestBounds = screen.getPrimaryDisplay().workArea;
      }
      // Vertical roaming: drift the pet up and down between the top and bottom
      // of the current display, bouncing at each edge. The sprite keeps its
      // facing (no horizontal flip), so no 'direction' event is sent here.
      const minY = nearestBounds.y;
      const maxY = nearestBounds.y + nearestBounds.height;
      // Self-healing sub-pixel tracker: if our tracked value has drifted from
      // where the window actually is (a drag or fling moved it), resync.
      let basePetTop = currentPetTopPrecise;
      if (!Number.isFinite(basePetTop) || Math.abs(basePetTop - nativePetTop) > 1.5) {
        basePetTop = nativePetTop;
      }
      let desiredPetTop = basePetTop + verticalDirection * config.pet.speed;
      const probe = calculateVerticalRoamPlacement(desiredPetTop, { minY, maxY }, petMetrics);
      if (probe.hitTop) {
        desiredPetTop = probe.petTop;
        verticalDirection = 1;
      } else if (probe.hitBottom) {
        desiredPetTop = probe.petTop;
        verticalDirection = -1;
      }
      const placement = projectPetWindowPosition(
        wx,
        probe.windowY,
        probe.topOffset,
        petMetrics,
        workAreas,
      );
      applyProjectedPetPlacement(placement);
      syncAutomaticHoverState();
      return;
    }

    const newX = advanceFractionalCoordinate(currentX, wx, direction * config.pet.speed);
    const topOffset = Number.isFinite(petTopOffset) ? petTopOffset : petMetrics.topMargin;
    const placement = projectPetWindowPosition(
      newX,
      wy,
      topOffset,
      petMetrics,
      workAreas,
    );
    if (!placement) return;
    const intendedPetLeft = newX + petMetrics.offsetX;
    if (Math.abs(placement.petLeft - intendedPetLeft) > 1e-6) {
      direction *= -1;
      win.webContents.send('direction', direction);
    }

    applyProjectedPetPlacement(placement);
    syncAutomaticHoverState();
  }, TICK_MS);

  win.webContents.once('did-finish-load', () => {
    runtimeErrorNotifier.setReady();
    maybeSpeakStartupGreeting();
    scheduleReminders();
    scheduleIdleChatter();
    scheduleChatInvite();
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
    if (!isLiveWindow(win)) {
      clearInterval(flingIntervalId);
      flingIntervalId = null;
      paused = false;
      return;
    }

    const [x, y] = win.getPosition();
    const petMetrics = getPetMetrics();
    const topOffset = Number.isFinite(petTopOffset) ? petTopOffset : petMetrics.topMargin;
    const newX = x + flingVX;
    const newY = y + flingVY;
    const intendedPetLeft = newX + petMetrics.offsetX;
    const intendedPetTop = newY + topOffset;
    const placement = projectPetWindowPosition(newX, newY, topOffset, petMetrics);
    if (!placement) return;
    let bounced = false;

    if (Math.abs(placement.petLeft - intendedPetLeft) > 1e-6) {
      flingVX = -flingVX * FLING_BOUNCE_DAMPING;
      bounced = true;
    }
    if (Math.abs(placement.petTop - intendedPetTop) > 1e-6) {
      flingVY = -flingVY * FLING_BOUNCE_DAMPING;
      bounced = true;
    }

    applyProjectedPetPlacement(placement);
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
      if (Number.isFinite(placement.windowY)) currentY = roundWindowCoordinate(placement.windowY);
      paused = false;
      // Only re-check hover once, right as it comes to rest - calling this
      // on every single tick churned setIgnoreMouseEvents 30+ times a
      // second and seemed to race with real click delivery.
      syncHoverState();
    }
  }, TICK_MS);
}

function scheduleReminders() {
  clearTimeout(reminderTimer);

  const tick = () => {
    const now = new Date();
    maybeSpeakStartupGreeting(now);
    const reminder = reminderScheduler.poll(now, config.schedule);
    if (!reminder) return;
    speak(reminder.event, reminder.context, {
      priority: SPEECH_PRIORITY.schedule,
      durationMs: 9000,
      replaceKey: reminder.event,
    });
  };

  const queueNextTick = () => {
    const now = new Date();
    const msUntilNextMinute = 60000 - (now.getSeconds() * 1000 + now.getMilliseconds());
    reminderTimer = setTimeout(() => {
      tick();
      queueNextTick();
    }, msUntilNextMinute);
  };

  tick();
  queueNextTick();
}

function scheduleIdleChatter() {
  clearTimeout(idleChatterTimer);
  idleChatterTimer = null;
  if (!config.language.idleEnabled) return;
  const minMs = config.language.idleMinMinutes * 60 * 1000;
  const maxMs = config.language.idleMaxMinutes * 60 * 1000;
  const delay = minMs + Math.random() * (maxMs - minMs);
  idleChatterTimer = setTimeout(() => {
    idleChatterTimer = null;
    if (isIdleSpeechPaused() || flingIntervalId) {
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
      speakContextualIdleChatter(dateContext);
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

function refreshRoutinesAfterWake(wakeDate, inactiveSince) {
  scheduleReminders();
  scheduleIdleChatter();
  scheduleChatInvite();
  if (clockService) {
    try {
      clockService.refreshAfterWake();
    } catch (error) {
      reportRuntimeError('Clock wake refresh', error);
    }
  }
  if (calendarService) {
    calendarService.refreshAfterWake(wakeDate, inactiveSince).catch((error) => {
      reportRuntimeError('Calendar wake refresh', error);
    });
  }
}

function speakAfterWake() {
  const now = Date.now();
  if (now - lastWakeSpokenAt < 2000) return;
  lastWakeSpokenAt = now;
  const inactiveSince = lockedAt;
  const lockedSeconds = inactiveSince ? Math.max(0, Math.round((now - inactiveSince) / 1000)) : 0;
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
  refreshRoutinesAfterWake(
    new Date(now),
    inactiveSince ? new Date(inactiveSince) : null,
  );
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
  agentPaused = shouldPauseAgentMovement(snapshot, config.pet);
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

const AGENT_SOUND_THROTTLE_MS = 300;
let lastAgentSoundAt = 0;

// Plays a short system chime for important agent cues. Completion and
// needs-input notifications have separate settings, because one says "done"
// and the other says "come back and approve this". Kept out of the speech
// pipeline on purpose: the bubble is throttled/replaced per event, but the
// sound is a plain fire-and-forget cue.
function playAgentSoundCue(scope, soundKey, fallbackSoundId, options = {}) {
  const setting = config.sound?.[soundKey];
  if (!setting || !setting.enabled) return;
  if (!options.allowDuringQuiet && isInQuietHours(new Date(), config.quietHours)) return;
  const now = Date.now();
  if (now - lastAgentSoundAt < AGENT_SOUND_THROTTLE_MS) return;
  const soundPath = taskCompleteSoundPath(setting.soundId) || taskCompleteSoundPath(fallbackSoundId);
  if (!soundPath) return;
  lastAgentSoundAt = now;
  playTaskSoundFile(soundPath, {
    execFile,
    beep: () => shell.beep(),
    onError: (error) => reportRuntimeError(scope, error),
  });
}

function playTaskCompleteSound() {
  playAgentSoundCue('Task completion sound', 'taskComplete', DEFAULT_TASK_COMPLETE_SOUND_ID);
}

function playTaskNotificationSound() {
  playAgentSoundCue('Task needs-input sound', 'needsInput', DEFAULT_NEEDS_INPUT_SOUND_ID, { allowDuringQuiet: true });
}

function emitTaskStatus(status = getVisibleTaskStatus()) {
  if (win && !win.isDestroyed()) win.webContents.send('task-status', status);
}

function emitPetEffect(effect) {
  if (win && !win.isDestroyed()) win.webContents.send('pet-effect', effect);
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
  const soundCue = getTaskSoundCue(transition.type);
  if (soundCue === 'needsInput') playTaskNotificationSound();
  else if (soundCue === 'taskComplete') playTaskCompleteSound();

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
    emitPetEffect({ type: 'task-completed', all: false });
    speak('agent.completed', context, { ...speechOptions, replaceKey: 'agent.completed' });
  } else if (transition.type === 'allCompleted') {
    emitPetEffect({ type: 'task-completed', all: true });
    speak('agent.allCompleted', context, {
      ...speechOptions,
      replaceKey: 'agent.allCompleted',
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
  taskLeasePollEpoch.invalidate();
  taskTracker.pruneStale(2 * 60 * 60 * 1000, Date.now(), 8 * 60 * 60 * 1000);
  if (taskLeaseDirectory) pruneTaskLeases(taskLeaseDirectory);
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

function rememberAgentEvent(event) {
  processedAgentEvents.remember(event);
}

function hasProcessedAgentEvent(event) {
  return processedAgentEvents.has(event);
}

function noteAgentConnection(event) {
  const connectionProvider = getConnectionProvider(event.provider);
  connectionHealth.noteEvent(connectionProvider);
  emitConnectionHealth(connectionProvider);
}

function applyTaskLeaseRecords(records, initial = false) {
  const activeEvents = [];
  for (const record of records) {
    const { event } = record;
    if (!isProviderEnabled(event.provider)) continue;
    if (['ended', 'completed', 'failed'].includes(event.event)) {
      if (!hasProcessedAgentEvent(event)) {
        noteAgentConnection(event);
        taskTracker.handle(event);
        rememberAgentEvent(event);
      }
      continue;
    }
    if (hasProcessedAgentEvent(event)) continue;
    noteAgentConnection(event);
    if (initial) {
      activeEvents.push(event);
    } else {
      const taskExists = taskTracker.getTasks().some((task) => task.key === taskTracker.taskKey(event));
      if (taskExists) {
        taskTracker.handle(event);
      } else if (event.event === 'needs_input') {
        taskTracker.restore([{
          ...event,
          event: 'started',
          timestamp: Number.isFinite(event.startedAt) ? event.startedAt : event.timestamp,
        }]);
        taskTracker.handle(event);
      } else {
        const snapshot = taskTracker.restore([event]);
        updateAgentState(snapshot);
        emitTaskStatus();
      }
    }
    rememberAgentEvent(event);
  }
  if (activeEvents.length > 0) taskTracker.restore(activeEvents);
}

function recoverTaskLeases(leaseDirectory, providers = null) {
  const records = readTaskLeases(leaseDirectory);
  applyTaskLeaseRecords(
    providers
      ? records.filter((record) => providers.has(record.event.provider))
      : records,
    true,
  );
}

async function pollTaskLeases(leaseDirectory) {
  if (taskLeasePollInFlight) return;
  taskLeasePollInFlight = true;
  try {
    await taskLeasePollEpoch.scanAndApply(
      () => readTaskLeasesAsync(leaseDirectory),
      (records) => applyTaskLeaseRecords(records),
    );
  } finally {
    taskLeasePollInFlight = false;
  }
}

function pruneTaskLeases(leaseDirectory) {
  if (taskLeasePruneInFlight) return;
  const senderPath = getAgentEventSenderPath();
  if (!fs.existsSync(senderPath)) return;
  taskLeasePruneInFlight = true;
  execFile(
    senderPath,
    ['--prune', '--lease-directory', leaseDirectory],
    { timeout: 2000, windowsHide: true },
    (error) => {
      taskLeasePruneInFlight = false;
      if (error) reportRuntimeError('Task lease cleanup', error);
    },
  );
}

function setupAgentBridge() {
  taskTracker = new TaskTracker(handleTaskTransition);
  const leaseDirectory = path.join(app.getPath('userData'), 'agent-task-leases');
  taskLeaseDirectory = leaseDirectory;
  try {
    recoverTaskLeases(leaseDirectory);
  } catch (error) {
    reportRuntimeError('Task lease recovery', error);
  }
  updateAgentState(taskTracker.snapshot());
  emitTaskStatus();
  agentBridge = new AgentBridge(path.join(app.getPath('userData'), 'agent-events.sock'), {
    onEvent: (event) => {
      taskLeasePollEpoch.invalidate();
      if (!isProviderEnabled(event.provider)) return;
      noteAgentConnection(event);
      const result = taskTracker.handleWithResult(event);
      if (result.accepted) rememberAgentEvent(event);
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
      if (settingsWin && !settingsWin.isDestroyed()) {
        settingsWin.webContents.send('integration-status', { calendar: calendarStatus, agentBridge: agentBridgeStatus });
      }
    });
  taskMaintenanceTimer = setInterval(runTaskMaintenance, 5 * 60 * 1000);
  taskLeasePollTimer = setInterval(() => {
    pollTaskLeases(leaseDirectory).catch((error) => {
      reportRuntimeError('Task lease recovery', error);
    });
  }, 1000);
  pruneTaskLeases(leaseDirectory);
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
        setAgentIntegrationReceiving(provider, true);
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
          receiveEnabled: true,
        };
      }
    }
    if (provider === 'claude') {
      status = await integrationManager.inspect('claude');
      if (status.state === 'connected' && !force) {
        setAgentIntegrationReceiving(provider, true);
        return { ...status, changed: false, restartRequired: false, receiveEnabled: true };
      }
      const operation = status.state === 'legacy' ? 'migrate' : force ? 'repair' : 'install';
      const prepared = integrationManager.prepareClaudeTerminalAction(process.execPath, operation);
      const openError = await shell.openPath(prepared.commandPath);
      if (openError) throw new Error(`无法打开 Terminal 安装窗口：${openError}`);
      setAgentIntegrationReceiving(provider, true);
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
        receiveEnabled: true,
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
    setAgentIntegrationReceiving(provider, true);
    return { ...result, receiveEnabled: true };
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
      setAgentIntegrationReceiving(provider, false);
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
        receiveEnabled: false,
      };
    }

    const status = await integrationManager.inspect(provider);
    if (provider === 'codex' && status.state === 'cli-missing') {
      const prepared = integrationManager.prepare('codex');
      const installUrl = `codex://plugins/${PLUGIN_NAME}?marketplacePath=${encodeURIComponent(prepared.marketplacePath)}`;
      await shell.openExternal(installUrl);
      setAgentIntegrationReceiving(provider, false);
      return {
        ...status,
        state: 'opened-disconnect',
        operation: 'disconnect',
        changed: false,
        receiveEnabled: false,
      };
    }

    const result = await integrationManager.uninstall(provider);
    setAgentIntegrationReceiving(provider, false);
    connectionHealth.clear(provider);
    emitConnectionHealth(provider);
    return { ...result, operation: 'disconnect', receiveEnabled: false };
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
  return connectionHealth.decorate(provider, {
    ...result,
    bundledVersion,
    updateAvailable,
    receiveEnabled: isProviderEnabled(provider),
  });
}

async function testAgentIntegration(provider) {
  if (!isProviderEnabled(provider)) throw new Error('任务状态接收已暂停，请先恢复接收');
  const status = await integrationManager.inspect(provider);
  const health = connectionHealth.snapshot(provider);
  if (status.state !== 'connected' && health.health !== 'active') {
    throw new Error('请先安装并启用状态插件');
  }
  return connectionHealth.decorate(provider, {
    ...status,
    ...connectionHealth.startTest(provider),
    receiveEnabled: true,
  });
}

if (hasSingleInstanceLock) app.on('second-instance', revealExistingInstance);

if (hasSingleInstanceLock) app.whenReady().then(() => {
  if (app.dock) app.dock.hide();
  configStore = new ConfigStore(app.getPath('userData'));
  config = configStore.load();
  if (configStore.loadWarning) reportRuntimeError('Settings', configStore.loadWarning);
  let startupConfigNeedsSave = false;
  startupGreetingStore = new StartupGreetingStore(app.getPath('userData'));
  startupGreetingStore.load();
  if (startupGreetingStore.loadWarning) {
    runtimeWarnings.set('startupGreeting', startupGreetingStore.loadWarning);
    reportRuntimeError('Startup greeting state', startupGreetingStore.loadWarning);
  }
  const activeCharacterId = loadConfiguredCharacter(config.pet.characterPackId);
  if (activeCharacterId !== config.pet.characterPackId) {
    config = { ...config, pet: { ...config.pet, characterPackId: activeCharacterId } };
    startupConfigNeedsSave = true;
  }
  const selectedCharacterName = characterPack.manifest.displayName;
  const fallbackCharacterPack = activeCharacterId === DEFAULT_CHARACTER_PACK_ID
    ? characterPack
    : loadCharacterPack(CHARACTERS_ROOT, DEFAULT_CHARACTER_PACK_ID);
  const petGeometryRepair = repairLoadedPetConfigWithFallback(
    config,
    { id: activeCharacterId, size: characterPack.manifest.size },
    {
      id: fallbackCharacterPack.manifest.id,
      size: fallbackCharacterPack.manifest.size,
    },
    PET_WINDOW_GEOMETRY,
  );
  if (petGeometryRepair.changed) {
    config = petGeometryRepair.config;
    startupConfigNeedsSave = true;
    if (petGeometryRepair.characterChanged) {
      characterPack = fallbackCharacterPack;
      runtimeWarnings.set(
        'petGeometry',
        `形象“${selectedCharacterName}”无法同时容纳角色、任务气泡和台词，已改用默认形象“${characterPack.manifest.displayName}”。`,
      );
    } else {
      runtimeWarnings.set(
        'petGeometry',
        `形象“${characterPack.manifest.displayName}”在 ${Math.round(petGeometryRepair.previousScale * 100)}% 时超出桌宠窗口，已自动调整为 ${Math.round(petGeometryRepair.maxScale * 100)}%。`,
      );
    }
  }
  const activeLanguageId = loadConfiguredLanguage(config.language.packId);
  if (activeLanguageId !== config.language.packId) {
    config = { ...config, language: { ...config.language, packId: activeLanguageId } };
    startupConfigNeedsSave = true;
  }
  if (startupConfigNeedsSave) {
    try {
      config = configStore.save(config);
      runtimeWarnings.clear('petGeometrySave');
    } catch (error) {
      runtimeWarnings.set('petGeometrySave', `自动修正后的设置无法保存，下次启动会再尝试：${error.message}`);
      reportRuntimeError('Startup settings repair', error);
    }
  }
  if (config.startup.launchAtLogin) {
    try {
      syncLaunchAtLogin(true);
    } catch (error) {
      runtimeWarnings.set('startup', `无法同步登录启动设置：${error.message}`);
      reportRuntimeError('Launch at login', error);
    }
  }
  updateAgentState(currentAgentSnapshot);
  setupClockService();

  ipcMain.handle('character-pack:get', () => getCharacterPayload());
  ipcMain.handle('pet-config:get', () => getPetConfigPayload());
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
  ipcMain.handle('settings:open-clock', (event) => {
    assertSettingsSender(event);
    createClockWindow();
    return true;
  });
  ipcMain.handle('clock:get', (event) => {
    assertClockSender(event);
    return getClockWindowPayload();
  });
  ipcMain.handle('clock:alarm-create', (event, input) => {
    assertClockSender(event);
    return getClockWindowPayload(clockService.createAlarm(input));
  });
  ipcMain.handle('clock:alarm-update', (event, id, patch) => {
    assertClockSender(event);
    return getClockWindowPayload(clockService.updateAlarm(id, patch));
  });
  ipcMain.handle('clock:alarm-delete', (event, id) => {
    assertClockSender(event);
    return getClockWindowPayload(clockService.deleteAlarm(id));
  });
  ipcMain.handle('clock:timer-start', (event, input) => {
    assertClockSender(event);
    return getClockWindowPayload(clockService.startTimer(input));
  });
  ipcMain.handle('clock:timer-pause', (event) => {
    assertClockSender(event);
    return getClockWindowPayload(clockService.pauseTimer());
  });
  ipcMain.handle('clock:timer-resume', (event) => {
    assertClockSender(event);
    return getClockWindowPayload(clockService.resumeTimer());
  });
  ipcMain.handle('clock:timer-extend', (event, minutes) => {
    assertClockSender(event);
    return getClockWindowPayload(clockService.extendTimer(minutes));
  });
  ipcMain.handle('clock:timer-cancel', (event) => {
    assertClockSender(event);
    return getClockWindowPayload(clockService.cancelTimer());
  });
  ipcMain.handle('clock:alert-snooze', (event, id, minutes) => {
    assertClockSender(event);
    return getClockWindowPayload(clockService.snoozeAlert(id, minutes));
  });
  ipcMain.handle('clock:alert-dismiss', (event, id) => {
    assertClockSender(event);
    return getClockWindowPayload(clockService.dismissAlert(id));
  });
  ipcMain.handle('clock:preferences-update', (event, preferences) => {
    assertClockSender(event);
    return getClockWindowPayload(clockService.updatePreferences(preferences));
  });
  ipcMain.handle('clock:preview-sound', (event, soundId) => {
    assertClockSender(event);
    const soundPath = taskCompleteSoundPath(soundId);
    if (!soundPath) return false;
    return playTaskSoundFile(soundPath, {
      execFile,
      beep: () => shell.beep(),
      onError: (error) => reportRuntimeError('Clock sound preview', error),
    });
  });
  ipcMain.handle('clock-summary:get', (event) => {
    assertPetSender(event);
    return getClockSummaryPayload();
  });
  ipcMain.handle('clock-alert:snooze', (event, id, minutes) => {
    assertPetSender(event);
    return getClockSummaryPayload(clockService.snoozeAlert(id, minutes));
  });
  ipcMain.handle('clock-alert:dismiss', (event, id) => {
    assertPetSender(event);
    return getClockSummaryPayload(clockService.dismissAlert(id));
  });
  // The DIY editor draws a live preview, so it needs the pack's own art. Only
  // the settings window may ask, and only for a pack that actually exists.
  ipcMain.handle('settings:character-art', (event, packId) => {
    assertSettingsSender(event);
    try {
      const pack = loadCharacterPack(CHARACTERS_ROOT, packId);
      return {
        id: pack.manifest.id,
        svg: pack.svg,
        size: pack.manifest.size,
        diy: pack.manifest.diy || null,
        accessories: pack.manifest.accessories || null,
      };
    } catch (error) {
      console.error(`Cannot preview character pack ${packId}: ${error.message}`);
      return null;
    }
  });
  ipcMain.handle('settings:preview-sound', (event, soundId) => {
    assertSettingsSender(event);
    // A manual preview always plays: it deliberately ignores the enabled
    // toggle and quiet hours, since the user explicitly asked to hear it.
    const soundPath = taskCompleteSoundPath(soundId);
    if (!soundPath) return false;
    return playTaskSoundFile(soundPath, {
      execFile,
      beep: () => shell.beep(),
      onError: (error) => reportRuntimeError('Sound preview', error),
    });
  });
  ipcMain.handle('app-update:check', (event) => {
    assertSettingsSender(event);
    return checkForAppUpdate();
  });
  ipcMain.handle('app-update:install', async (event) => {
    assertSettingsSender(event);
    try {
      return await installGithubUpdate();
    } catch (error) {
      reportRuntimeError('App update install', error);
      return {
        state: 'error',
        message: error?.message || '自动更新没有完成，请稍后重试',
      };
    }
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
      const selectedCharacter = loadCharacterPack(CHARACTERS_ROOT, nextConfig.pet.characterPackId);
      const saved = persistConfig(nextConfig, selectedCharacter.manifest.size);
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
      const defaultCharacter = loadCharacterPack(CHARACTERS_ROOT, DEFAULT_CONFIG.pet.characterPackId);
      const reset = persistConfig(DEFAULT_CONFIG, defaultCharacter.manifest.size);
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
  ipcMain.handle('agent-integrations:set-receiving', (event, provider, enabled) => {
    assertSettingsSender(event);
    if (typeof enabled !== 'boolean') throw new Error('接收状态必须是布尔值');
    setAgentIntegrationReceiving(provider, enabled);
    if (!enabled) {
      connectionHealth.clear(provider);
      emitConnectionHealth(provider);
    }
    return inspectAgentIntegration(provider);
  });
  createApplicationMenu();
  createTray();
  createWindow();
  setupDisplayMonitors();
  setupSystemMonitors();
  setupCalendarService();
  integrationManager = new IntegrationManager({
    resourcesRoot: getIntegrationResourcesRoot(),
    dataRoot: path.join(app.getPath('userData'), 'managed-integrations'),
    eventSenderPath: getAgentEventSenderPath(),
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
  clearTimeout(chatInviteTimer);
  clearTimeout(reminderTimer);
  clearTimeout(displayRecoveryTimer);
  clearTimeout(contextMenuPauseTimer);
  stopPetMotionTimers();
  clearInterval(batteryPollTimer);
  clearInterval(taskMaintenanceTimer);
  clearInterval(taskLeasePollTimer);
  if (clockService) clockService.stop();
  if (calendarService) calendarService.stop();
  if (agentBridge) agentBridge.stop();
  if (speechQueue) speechQueue.clear();
});
