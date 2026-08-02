const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const {
  bootstrapRenderer,
  createAsyncGuard,
  createChatInviteIntent,
} = require('../src/core/renderer-runtime');

const rendererSource = fs.readFileSync(path.join(__dirname, '..', 'src', 'renderer.js'), 'utf8');
const indexSource = fs.readFileSync(path.join(__dirname, '..', 'src', 'index.html'), 'utf8');

function classList() {
  const values = new Set();
  return {
    add: (...names) => names.forEach((name) => values.add(name)),
    remove: (...names) => names.forEach((name) => values.delete(name)),
    contains: (name) => values.has(name),
    toggle: (name, force) => {
      if (force === false) values.delete(name);
      else if (force === true || !values.has(name)) values.add(name);
      else values.delete(name);
    },
  };
}

function element() {
  return {
    addEventListener() {},
    append() {},
    classList: classList(),
    dataset: {},
    hidden: false,
    innerHTML: '',
    offsetWidth: 1,
    querySelector: () => null,
    querySelectorAll: () => [],
    remove() {},
    removeAttribute() {},
    setAttribute() {},
    style: {
      opacity: '0',
      setProperty() {},
    },
    textContent: '',
  };
}

function rejectingThenable(message) {
  let handled = false;
  const error = new Error(message);
  return {
    get handled() {
      return handled;
    },
    then(_resolve, reject) {
      if (typeof reject === 'function') {
        handled = true;
        queueMicrotask(() => reject(error));
      }
    },
  };
}

function createRendererHarness() {
  const pet = element();
  const bubble = element();
  const taskBubble = element();
  const clockElements = Object.fromEntries([
    'clock-alert',
    'clock-display',
    'clock-display-label',
    'clock-display-time',
    'clock-alert-kind',
    'clock-alert-title',
    'clock-alert-snooze',
    'clock-alert-dismiss',
    'completion-effect',
    'performance-panel',
    'performance-system',
    'performance-app',
  ].map((id) => [id, element()]));
  const body = element();
  const svgRoot = { outerHTML: '<svg></svg>' };
  pet.querySelector = (selector) => (selector === 'svg' ? svgRoot : null);
  const listeners = {};
  const callbacks = {};
  const consoleErrors = [];
  const bootstrapRejections = {
    agent: rejectingThenable('agent unavailable'),
    status: rejectingThenable('status unavailable'),
    config: rejectingThenable('config unavailable'),
  };
  let openChatCount = 0;
  let petClickedCount = 0;
  let clock = 1000;
  let getCharacterPack = () => new Promise(() => {});
  let timerId = 0;
  const timers = new Map();

  pet.addEventListener = (name, callback) => {
    listeners[name] = callback;
  };

  const document = {
    body,
    documentElement: element(),
    addEventListener(name, callback) {
      listeners[`document:${name}`] = callback;
    },
    createElement: () => element(),
    elementFromPoint: () => null,
    getElementById(id) {
      if (id === 'pet') return pet;
      if (id === 'bubble') return bubble;
      if (id === 'task-bubble') return taskBubble;
      if (clockElements[id]) return clockElements[id];
      return null;
    },
    querySelectorAll: () => [],
  };

  const callbackMethods = [
    'onAgentState',
    'onBump',
    'onCharacterPack',
    'onChatInvite',
    'onCheckHover',
    'onClockState',
    'onDialogueReaction',
    'onDirection',
    'onPetAction',
    'onPetEffect',
    'onPetConfig',
    'onPetLayout',
    'onPerformanceSample',
    'onSpeech',
    'onTaskStatus',
  ];
  const petAPI = {
    getAgentState: () => bootstrapRejections.agent,
    getCharacterPack: () => getCharacterPack(),
    getClockSummary: () => Promise.resolve({
      timer: null,
      nextAlarm: null,
      alerts: [],
      hasEnabledAlarm: false,
    }),
    getPetConfig: () => bootstrapRejections.config,
    getPerformanceSample: () => Promise.resolve(null),
    getTaskStatus: () => bootstrapRejections.status,
    openChat: () => {
      openChatCount += 1;
    },
    petClicked: () => {
      petClickedCount += 1;
    },
    reportVisualBounds() {},
    dismissClockAlert: () => Promise.resolve({
      timer: null,
      nextAlarm: null,
      alerts: [],
      hasEnabledAlarm: false,
    }),
    snoozeClockAlert: () => Promise.resolve({
      timer: null,
      nextAlarm: null,
      alerts: [],
      hasEnabledAlarm: false,
    }),
    setPaused() {},
  };
  for (const method of callbackMethods) {
    petAPI[method] = (callback) => {
      callbacks[method] = callback;
    };
  }

  const context = {
    accessoryModel: {
      applyAccessoriesToSvg() {},
      normalizeAccessories: () => ({ equipped: {} }),
      sanitizeSvgTree: (root) => root,
      withAccessoryEquipped: (spec) => spec,
    },
    clearTimeout(id) {
      timers.delete(id);
    },
    console: { error: (...args) => consoleErrors.push(args) },
    diyModel: { applyDiyToSvg() {} },
    document,
    DOMParser: class {
      parseFromString() {
        return {
          documentElement: svgRoot,
          querySelector: () => null,
        };
      }
    },
    expressionMoods: { pickExpression: () => null },
    Math,
    petVisualBounds: { calculateVisualTopOverflow: () => 0 },
    performance: { now: () => clock },
    Promise,
    queueMicrotask,
    rendererRuntime: {
      bootstrapRenderer,
      createAsyncGuard,
      createChatInviteIntent,
    },
    setInterval() {
      timerId += 1;
      return timerId;
    },
    setTimeout(callback) {
      timerId += 1;
      timers.set(timerId, callback);
      return timerId;
    },
    taskCarouselModel: {
      buildCarouselLayout: () => ({ entries: [], frontIndex: 0, frontTaskKey: null, position: 0, total: 0 }),
      nextTaskKey: () => null,
    },
    uiI18n: {
      DEFAULT_LOCALE: 'zh-CN',
      applyDocument: (_document, locale) => (locale === 'en' ? 'en' : 'zh-CN'),
      t: (_locale, key) => key,
    },
    window: { petAPI },
  };

  vm.runInNewContext(rendererSource, context, { filename: 'renderer.js' });
  return {
    bootstrapRejections,
    callbacks,
    consoleErrors,
    clickPet: () => listeners.click(),
    failCharacterPack(error = new Error('character pack unavailable')) {
      getCharacterPack = () => Promise.reject(error);
    },
    get openChatCount() {
      return openChatCount;
    },
    get petClickedCount() {
      return petClickedCount;
    },
    runBubbleTimers() {
      const callbacksToRun = [...timers.values()];
      timers.clear();
      callbacksToRun.forEach((callback) => callback());
    },
  };
}

test('a non-invite bubble immediately invalidates the previous chat invitation', async () => {
  const harness = createRendererHarness();
  await new Promise((resolve) => setImmediate(resolve));

  harness.callbacks.onChatInvite({ text: '要聊聊嗎？', durationMs: 7000 });
  harness.callbacks.onSpeech({ text: '任務開始了。', durationMs: 7000 });
  harness.clickPet();

  assert.equal(harness.openChatCount, 0);
  assert.equal(harness.petClickedCount, 1);
});

test('the renderer runtime helper loads before the renderer entry point', () => {
  const helperIndex = indexSource.indexOf('core/renderer-runtime.js');
  const visualBoundsIndex = indexSource.indexOf('core/pet-visual-bounds.js');
  const rendererIndex = indexSource.indexOf('renderer.js');
  assert.ok(helperIndex >= 0);
  assert.ok(visualBoundsIndex >= 0);
  assert.ok(rendererIndex > helperIndex);
  assert.ok(rendererIndex > visualBoundsIndex);
});

test('hiding an invitation bubble immediately invalidates its click intent', async () => {
  const harness = createRendererHarness();
  await new Promise((resolve) => setImmediate(resolve));

  harness.callbacks.onChatInvite({ text: '要聊聊嗎？', durationMs: 7000 });
  harness.runBubbleTimers();
  harness.clickPet();

  assert.equal(harness.openChatCount, 0);
  assert.equal(harness.petClickedCount, 1);
});

test('all rejecting renderer bootstrap reads attach rejection handlers', async () => {
  const harness = createRendererHarness();
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(harness.bootstrapRejections.agent.handled, true);
  assert.equal(harness.bootstrapRejections.status.handled, true);
  assert.equal(harness.bootstrapRejections.config.handled, true);
});

test('bootstrap catches an asynchronous config apply failure and coalesces error notices', async () => {
  const errors = [];
  const guard = createAsyncGuard({
    noticeCooldownMs: 2500,
    now: () => 1000,
    reportError: (entry) => errors.push(entry),
  });
  const petAPI = {
    getAgentState: () => Promise.reject(new Error('agent unavailable')),
    getPetConfig: () => Promise.resolve({ customization: { body: {} } }),
    getTaskStatus: () => Promise.reject(new Error('status unavailable')),
  };

  await assert.doesNotReject(() => bootstrapRenderer({
    applyAgentState() {},
    applyPetConfig: () => Promise.reject(new Error('pack reload failed')),
    guard,
    installCharacterPack: () => Promise.reject(new Error('pack unavailable')),
    petAPI,
    renderTaskStatus() {},
  }));

  assert.deepEqual(
    errors.map((entry) => entry.label).sort(),
    ['install character pack', 'read agent state', 'read pet config', 'read task status'],
  );
  assert.equal(errors.filter((entry) => entry.shouldNotify).length, 1);
});

test('a config-driven character reinstall is returned to the renderer error guard', async () => {
  const harness = createRendererHarness();
  await new Promise((resolve) => setImmediate(resolve));
  harness.callbacks.onCharacterPack({
    accessories: [],
    manifest: { id: 'test-pet', size: { height: 70, width: 82 } },
    styles: [],
    svg: '<svg></svg>',
  });

  harness.failCharacterPack();
  harness.callbacks.onPetConfig({ customization: { body: { width: 1.1 } } });
  await new Promise((resolve) => setImmediate(resolve));

  assert.ok(harness.consoleErrors.some(([message]) => message.includes('apply pet config')));
});
