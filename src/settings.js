const form = document.getElementById('settings-form');
const status = document.getElementById('status');
const saveButton = form.querySelector('button[type="submit"]');
const resetButton = document.getElementById('reset-button');
const speedInput = document.getElementById('pet-speed');
const speedOutput = document.getElementById('speed-output');
const scaleInput = document.getElementById('pet-scale');
const scaleOutput = document.getElementById('scale-output');
const agentProviders = ['codex', 'claude'];
const integrationControls = Object.fromEntries(agentProviders.map((provider) => [provider, {
  primary: document.getElementById(`connect-${provider}`),
  repair: document.getElementById(`repair-${provider}`),
  disconnect: document.getElementById(`disconnect-${provider}`),
  details: document.getElementById(`${provider}-connection-details`),
}]));
const integrationResults = {};
const connectionTestTimers = {};
const integrationOperations = new Map();
let charactersById = new Map();
let activeSettingsCopy = null;
let diyMap = {};
let diyArt = null;
let accessoryMap = {};
let accessoryCatalog = [];
const diyModel = globalThis.diyModel;
const accessoryModel = globalThis.accessoryModel;
const panelTabs = [...document.querySelectorAll('.nav-item[data-panel]')];
const panels = [...document.querySelectorAll('.settings-panel[data-panel-name]')];

function byId(id) { return document.getElementById(id); }
function setChecked(id, value) { byId(id).checked = value; }
function setValue(id, value) { byId(id).value = value; }

function renderAppVersion(version) {
  if (typeof version !== 'string') return;
  byId('version-badge').textContent = `Pro${version}`;
}

function activatePanel(panelId, options = {}) {
  const activeTab = panelTabs.find((tab) => tab.dataset.panel === panelId) || panelTabs[0];
  for (const tab of panelTabs) {
    const selected = tab === activeTab;
    tab.setAttribute('aria-selected', String(selected));
    tab.tabIndex = selected ? 0 : -1;
  }
  for (const panel of panels) panel.hidden = panel.id !== `panel-${activeTab.dataset.panel}`;
  // The preview measures its own bounding boxes, which only works once the
  // panel is actually on screen.
  if (activeTab.dataset.panel === 'diy') renderDiyPreview();
  document.querySelector('.content-scroll').scrollTop = 0;
  if (options.focus) activeTab.focus();
}

function syncDependentControls() {
  const dependencies = [
    ['workday-greeting-enabled', 'workday-greeting-times'],
    ['dayoff-greeting-enabled', 'dayoff-greeting-times'],
    ['quiet-enabled', 'quiet-times'],
    ['idle-enabled', 'idle-time-fields'],
    ['sound-task-complete-enabled', 'sound-task-complete-fields'],
  ];
  for (const [toggleId, groupId] of dependencies) {
    const enabled = byId(toggleId).checked;
    if (!enabled) {
      if (groupId === 'workday-greeting-times') normalizeTimeRange(groupId, '07:00', '11:00');
      if (groupId === 'dayoff-greeting-times') normalizeTimeRange(groupId, '07:00', '18:00');
      if (groupId === 'quiet-times') normalizeTimeRange(groupId, '22:30', '08:30', false);
      if (groupId === 'idle-time-fields') normalizeIdleRange();
    }
    byId(groupId).dataset.disabled = String(!enabled);
    byId(groupId).setAttribute('aria-disabled', String(!enabled));
    byId(groupId).querySelectorAll('input, select, button').forEach((control) => { control.disabled = !enabled; });
  }
  updateFormValidity();
}

function normalizeTimeRange(groupId, defaultStart, defaultEnd, requireForward = true) {
  const inputs = [...byId(groupId).querySelectorAll('input[type="time"]')];
  const invalid = inputs.length !== 2
    || !inputs[0].value
    || !inputs[1].value
    || (requireForward && inputs[0].value >= inputs[1].value);
  if (invalid && inputs.length === 2) {
    inputs[0].value = defaultStart;
    inputs[1].value = defaultEnd;
  }
}

function normalizeIdleRange() {
  const minInput = byId('idle-min');
  const maxInput = byId('idle-max');
  const min = Number(minInput.value);
  const max = Number(maxInput.value);
  if (!Number.isFinite(min) || min < 1 || min > 180 || !Number.isFinite(max) || max < 1 || max > 240 || min > max) {
    minInput.value = '12';
    maxInput.value = '35';
  }
}

function setRangeValidity(startId, endId, message) {
  const start = byId(startId);
  const end = byId(endId);
  start.setCustomValidity('');
  end.setCustomValidity('');
  if (!start.value) start.setCustomValidity('请选择开始时间。');
  if (!end.value) end.setCustomValidity('请选择结束时间。');
  if (start.value && end.value && start.value >= end.value) end.setCustomValidity(message);
}

function updateFormValidity() {
  setRangeValidity('workday-greeting-start', 'workday-greeting-end', '结束时间必须晚于开始时间。');
  setRangeValidity('dayoff-greeting-start', 'dayoff-greeting-end', '结束时间必须晚于开始时间。');
  const idleMin = byId('idle-min');
  const idleMax = byId('idle-max');
  idleMax.setCustomValidity(Number(idleMin.value) > Number(idleMax.value) ? '最长间隔不能短于最短间隔。' : '');
}

function validateVisibleForm() {
  updateFormValidity();
  const invalid = form.querySelector('input:invalid, select:invalid');
  if (!invalid) return true;
  const panel = invalid.closest('.settings-panel');
  if (panel) activatePanel(panel.id.replace('panel-', ''));
  invalid.reportValidity();
  invalid.focus();
  return false;
}

function applyCharacterCopy(characterId) {
  const copy = charactersById.get(characterId)?.settingsCopy;
  if (!copy) return;
  activeSettingsCopy = copy;
  document.title = copy.windowTitle;
  byId('settings-title').textContent = copy.pageTitle;
  byId('settings-subtitle').textContent = copy.subtitle;
  byId('schedule-title').textContent = copy.scheduleTitle;
  byId('schedule-hint').textContent = copy.scheduleHint;
  byId('greeting-title').textContent = copy.greetingTitle || '每天第一次见面';
  byId('greeting-hint').textContent = copy.greetingHint || '在设定时段内当天第一次打开，角色会说一句早安。';
  byId('quiet-title').textContent = copy.quietTitle;
  byId('quiet-hint').textContent = copy.quietHint;
  byId('personality-title').textContent = copy.personalityTitle;
  byId('personality-hint').textContent = copy.personalityHint;
  byId('motion-title').textContent = copy.motionTitle;
  byId('motion-hint').textContent = copy.motionHint;
  byId('speed-label').textContent = copy.speedLabel;
  byId('roam-without-tasks-label').textContent = copy.roamWithoutTasksLabel;
  byId('roam-without-tasks').setAttribute('aria-label', copy.roamWithoutTasksLabel);
  byId('entry-hint').textContent = copy.entryHint;
}

function showStatus(message, isError = false) {
  status.textContent = message;
  status.classList.toggle('error', isError);
}

function setBusy(busy) {
  saveButton.disabled = busy;
  resetButton.disabled = busy;
}

function renderLanguages(languages, selectedId) {
  const select = byId('language-pack');
  select.replaceChildren();
  for (const language of languages) {
    const option = document.createElement('option');
    option.value = language.id;
    option.textContent = `${language.displayName} · ${language.locale}`;
    option.selected = language.id === selectedId;
    select.appendChild(option);
  }
}

function renderSounds(sounds, selectedId) {
  const select = byId('sound-task-complete-id');
  select.replaceChildren();
  for (const sound of sounds) {
    const option = document.createElement('option');
    option.value = sound.id;
    option.textContent = sound.label;
    option.selected = sound.id === selectedId;
    select.appendChild(option);
  }
}

function renderCharacters(characters, selectedId) {
  const select = byId('character-pack');
  charactersById = new Map(characters.map((character) => [character.id, character]));
  select.replaceChildren();
  for (const character of characters) {
    const option = document.createElement('option');
    option.value = character.id;
    option.textContent = character.displayName;
    option.dataset.defaultLanguagePack = character.defaultLanguagePack || '';
    option.selected = character.id === selectedId;
    select.appendChild(option);
  }
  applyCharacterCopy(select.value);
}

// --- 捏鱼 (DIY) ----------------------------------------------------------
// Edits live in `diyMap` keyed by character pack, and only reach the pet when
// the form is saved. The preview re-parses the pack's own art every time, so
// a shape preset can replace nodes without ever accumulating.

function currentDiySpec() {
  const packId = byId('character-pack').value;
  if (!diyMap[packId]) diyMap[packId] = diyModel.defaultDiy();
  return diyMap[packId];
}

function formatDiyValue(field, value) {
  return field.kind === 'ratio' ? `${Math.round(value * 100)}%` : `${value > 0 ? '+' : ''}${value}`;
}

function buildDiyShapeField(groupName, group, spec) {
  const options = diyModel.listShapeOptions(diyArt && diyArt.diy, groupName);
  if (options.length === 0) return null;

  const label = document.createElement('label');
  label.className = 'field';
  label.append(group.label);

  const select = document.createElement('select');
  select.dataset.diyShape = groupName;
  for (const option of options) {
    const element = document.createElement('option');
    element.value = option.id;
    element.textContent = option.label;
    select.appendChild(element);
  }
  // An id from another pack won't exist here; fall back to the first preset.
  select.value = options.some((option) => option.id === spec[groupName].shape)
    ? spec[groupName].shape
    : options[0].id;
  spec[groupName].shape = select.value;

  select.addEventListener('change', () => {
    currentDiySpec()[groupName].shape = select.value;
    renderDiyPreview();
  });
  label.appendChild(select);
  return label;
}

function buildDiySlider(part, field, spec) {
  const label = document.createElement('label');
  label.className = 'field range-field';

  const heading = document.createElement('span');
  const name = document.createElement('span');
  name.textContent = field.label;
  const output = document.createElement('output');
  output.textContent = formatDiyValue(field, spec[part][field.key]);
  heading.append(name, output);

  const input = document.createElement('input');
  input.type = 'range';
  input.min = String(field.min);
  input.max = String(field.max);
  input.step = String(field.step);
  input.value = String(spec[part][field.key]);
  input.addEventListener('input', () => {
    const value = Number(input.value);
    currentDiySpec()[part][field.key] = value;
    output.textContent = formatDiyValue(field, value);
    renderDiyPreview();
  });

  label.append(heading, input);
  return label;
}

function renderDiyControls() {
  const container = byId('diy-controls');
  container.replaceChildren();
  const spec = currentDiySpec();

  for (const group of diyModel.DIY_CONTROLS) {
    const card = document.createElement('div');
    card.className = 'card diy-group';

    const heading = document.createElement('h3');
    heading.textContent = group.label;
    card.appendChild(heading);

    const shapeGroup = diyModel.SHAPE_GROUPS[group.part];
    if (shapeGroup) {
      const shapeField = buildDiyShapeField(group.part, shapeGroup, spec);
      if (shapeField) card.appendChild(shapeField);
    }

    const stack = document.createElement('div');
    stack.className = 'range-stack';
    for (const field of group.fields) stack.appendChild(buildDiySlider(group.part, field, spec));
    card.appendChild(stack);
    container.appendChild(card);
  }
}

function currentAccessorySpec() {
  const packId = byId('character-pack').value;
  if (!accessoryMap[packId]) accessoryMap[packId] = accessoryModel.defaultAccessories();
  return accessoryMap[packId];
}

function buildAccessorySlider(slotKey, field, settings) {
  const label = document.createElement('label');
  label.className = 'field range-field';

  const heading = document.createElement('span');
  const name = document.createElement('span');
  name.textContent = field.label;
  const output = document.createElement('output');
  output.textContent = formatDiyValue(field, settings[field.key]);
  heading.append(name, output);

  const input = document.createElement('input');
  input.type = 'range';
  input.min = String(field.min);
  input.max = String(field.max);
  input.step = String(field.step);
  input.value = String(settings[field.key]);
  input.addEventListener('input', () => {
    const value = Number(input.value);
    currentAccessorySpec()[slotKey][field.key] = value;
    output.textContent = formatDiyValue(field, value);
    renderDiyPreview();
  });

  label.append(heading, input);
  return label;
}

function renderAccessoryControls() {
  const container = byId('accessory-controls');
  container.replaceChildren();

  const slots = accessoryModel.getCharacterSlots({ accessories: diyArt && diyArt.accessories });
  if (!slots) {
    container.hidden = true;
    return;
  }
  container.hidden = false;

  const heading = document.createElement('h3');
  heading.textContent = '饰品';
  container.appendChild(heading);

  const spec = currentAccessorySpec();
  for (const slot of accessoryModel.ACCESSORY_SLOTS) {
    if (!slots[slot.key]) continue;
    const settings = spec[slot.key];

    const field = document.createElement('label');
    field.className = 'field';
    field.append(slot.label);

    const select = document.createElement('select');
    select.dataset.accessorySlot = slot.key;
    const none = document.createElement('option');
    none.value = '';
    none.textContent = slot.empty;
    select.appendChild(none);
    for (const item of accessoryCatalog.filter((entry) => entry.slot === slot.key)) {
      const option = document.createElement('option');
      option.value = item.id;
      option.textContent = item.displayName;
      select.appendChild(option);
    }
    select.value = [...select.options].some((option) => option.value === settings.id) ? settings.id : '';

    // Nudging an empty slot means nothing, so the sliders only appear once
    // something is actually being worn.
    const sliders = document.createElement('div');
    sliders.className = 'range-stack accessory-sliders';
    for (const sliderField of accessoryModel.ACCESSORY_FIELDS) {
      sliders.appendChild(buildAccessorySlider(slot.key, sliderField, settings));
    }
    sliders.hidden = !settings.id;

    select.addEventListener('change', () => {
      currentAccessorySpec()[slot.key].id = select.value || null;
      sliders.hidden = !select.value;
      renderDiyPreview();
    });

    field.appendChild(select);
    container.append(field, sliders);
  }
}

function renderDiyPreview() {
  const stage = byId('diy-preview');
  if (!diyArt) {
    stage.replaceChildren();
    return;
  }

  const parsed = new DOMParser().parseFromString(diyArt.svg, 'image/svg+xml');
  if (parsed.querySelector('parsererror')) {
    stage.replaceChildren();
    return;
  }

  const svg = document.importNode(parsed.documentElement, true);
  // Tears only belong to the "被揍" reaction; a resting portrait shouldn't cry.
  svg.querySelectorAll('.tears, .tear').forEach((node) => node.remove());
  stage.replaceChildren(svg);
  // getBBox only reports real numbers once the node is laid out, which is why
  // the SVG goes into the document before the spec is applied.
  diyModel.applyDiyToSvg(svg, currentDiySpec(), { diy: diyArt.diy });
  accessoryModel.applyAccessoriesToSvg(
    svg,
    { accessories: diyArt.accessories },
    accessoryCatalog,
    currentAccessorySpec(),
  );
}

async function loadDiy(packId) {
  const supported = Boolean(charactersById.get(packId)?.diy?.enabled);
  byId('diy-unsupported').hidden = supported;
  byId('diy-workspace').hidden = !supported;
  if (!supported) {
    diyArt = null;
    byId('diy-controls').replaceChildren();
    byId('accessory-controls').replaceChildren();
    byId('diy-preview').replaceChildren();
    return;
  }

  diyArt = await window.settingsAPI.getCharacterArt(packId);
  // The selection can change while the art request is in flight.
  if (byId('character-pack').value !== packId) return;
  renderDiyControls();
  renderAccessoryControls();
  renderDiyPreview();
}

function renderIntegrationStatus(integrationStatus = {}) {
  const labels = {
    disabled: '未启用',
    requesting: '正在请求日历权限…',
    authorized: '已授权，只在本机读取',
    notDetermined: '尚未决定权限',
    denied: '权限被拒绝',
    restricted: '权限受系统限制',
    writeOnly: '只有写入权限，无法读取',
    unknown: '权限状态未知',
    error: '连接失败，请查看日志',
  };
  const statusName = integrationStatus.calendar || 'disabled';
  byId('calendar-status').textContent = `日历：${labels[statusName] || labels.unknown}`;
  const bridgeLabels = {
    starting: '正在启动…',
    listening: '本地接收器已就绪（不代表平台已连接）',
    stopped: '未启动',
    error: '启动失败，请查看日志',
  };
  const bridgeStatus = integrationStatus.agentBridge || 'stopped';
  byId('agent-bridge-status').textContent = bridgeLabels[bridgeStatus] || bridgeLabels.error;
}

function formatLastEvent(timestamp) {
  if (!timestamp) return '尚未收到';
  return new Intl.DateTimeFormat('zh-CN', {
    month: 'numeric',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(timestamp));
}

function setConnectionStep(provider, stage, state, detail) {
  const element = byId(`${provider}-stage-${stage}`);
  element.dataset.state = state;
  element.querySelector('small').textContent = detail;
}

function renderAgentIntegration(provider, result) {
  integrationResults[provider] = result;
  const controls = integrationControls[provider];
  const statusElement = byId(`${provider}-install-status`);
  const verdictElement = byId(`${provider}-connection-verdict`);
  const technicalDetails = byId(`${provider}-technical-details`);
  const health = result.health || 'unavailable';
  const operation = integrationOperations.get(provider);
  const blocked = ['conflict', 'error', 'disabled', 'not-installed', 'legacy'].includes(result.state);
  const live = health === 'active' && !blocked && result.receiveEnabled !== false;
  const busy = Boolean(operation) || ['checking', 'opened', 'opened-disconnect', 'terminal-opened'].includes(result.state);
  const managedInstalled = result.state === 'connected'
    || result.state === 'disabled'
    || (result.state === 'cli-missing' && live);
  const presentedResult = operation
    ? { ...result, operationBusy: true, operation }
    : result;
  const presentation = window.integrationUI.describeAgentIntegration(provider, presentedResult, {
    lastEventLabel: formatLastEvent(result.lastEventAt),
  });

  if (typeof result.receiveEnabled === 'boolean') {
    setChecked(provider === 'codex' ? 'integration-codex' : 'integration-claude', result.receiveEnabled);
  }

  statusElement.textContent = presentation.summary;
  statusElement.classList.toggle('error', ['error', 'conflict'].includes(result.state) || health === 'test-timeout');
  verdictElement.textContent = presentation.verdict;
  verdictElement.dataset.state = presentation.verdictState;
  byId(`${provider}-next-step`).textContent = presentation.instruction;
  const conflictHelp = result.state === 'conflict'
    ? (provider === 'codex'
      ? `处理：在 Codex 插件页面移除“${result.pluginId || '同名插件'}”，然后点“重新检测连接状态”。`
      : `处理：在 Claude Code 插件管理中移除“${result.pluginId || '同名插件'}”，然后点“重新检测连接状态”。`)
    : null;
  technicalDetails.textContent = [
    result.pluginId ? `插件：${result.pluginId}` : null,
    result.version ? `版本：${result.version}` : null,
    result.error ? `详情：${result.error}` : null,
    conflictHelp,
  ].filter(Boolean).join(' · ') || '未检测到插件标识。';

  if (result.state === 'checking') setConnectionStep(provider, 'cli', 'pending', '正在检测…');
  else if (result.cliFound) setConnectionStep(provider, 'cli', 'done', '已找到命令行工具');
  else if (result.state === 'opened' || result.state === 'opened-disconnect') setConnectionStep(provider, 'cli', 'active', '已打开 Codex App 插件页');
  else if (live) setConnectionStep(provider, 'cli', 'done', '已由真实任务事件确认');
  else if (result.state === 'cli-missing') setConnectionStep(provider, 'cli', 'error', '未找到命令行工具');
  else if (result.state === 'error') setConnectionStep(provider, 'cli', 'error', '检测未完成');
  else setConnectionStep(provider, 'cli', 'pending', '尚未确认');

  if (result.state === 'connected') setConnectionStep(provider, 'plugin', 'done', result.version ? `已安装 v${result.version}` : '已安装并启用');
  else if (result.state === 'legacy') setConnectionStep(provider, 'plugin', 'active', result.version ? `检测到旧版 v${result.version}` : '检测到可升级的旧版');
  else if (result.state === 'disabled') setConnectionStep(provider, 'plugin', 'error', '已安装，但被停用');
  else if (result.state === 'conflict') setConnectionStep(provider, 'plugin', 'error', '同名插件来源冲突');
  else if (result.state === 'error') setConnectionStep(provider, 'plugin', 'error', '检测或操作失败');
  else if (result.state === 'opened' || result.state === 'terminal-opened') setConnectionStep(provider, 'plugin', 'active', '等待安装结果');
  else if (result.state === 'opened-disconnect') setConnectionStep(provider, 'plugin', 'active', '等待手动移除');
  else if (live) setConnectionStep(provider, 'plugin', 'done', '已由真实任务事件确认工作');
  else setConnectionStep(provider, 'plugin', 'pending', '尚未安装');

  if (result.receiveEnabled === false) {
    setConnectionStep(provider, 'trust', 'pending', '任务状态接收已暂停');
  } else if (live) {
    setConnectionStep(provider, 'trust', 'done', provider === 'codex' ? 'Hook 已通过真实事件验证' : '插件已在会话中生效');
  } else if (health === 'test-timeout') {
    setConnectionStep(provider, 'trust', 'error', provider === 'codex' ? '请检查 /hooks 是否已允许' : '请重新打开 Claude Code 会话');
  } else if (result.state === 'connected' || health === 'awaiting-event') {
    setConnectionStep(provider, 'trust', 'active', provider === 'codex' ? '请在 /hooks 中允许水滴鱼' : '请重新打开 Claude Code 会话');
  } else {
    setConnectionStep(provider, 'trust', 'pending', provider === 'codex' ? '安装后需要授权' : '安装后需要新会话');
  }

  if (result.receiveEnabled === false) setConnectionStep(provider, 'live', 'pending', '接收已暂停');
  else if (live) setConnectionStep(provider, 'live', 'done', `最近收到：${formatLastEvent(result.lastEventAt)}`);
  else if (health === 'awaiting-event') setConnectionStep(provider, 'live', 'active', '请触发一条真实任务状态');
  else if (health === 'test-timeout') setConnectionStep(provider, 'live', 'error', '60 秒内没有收到状态');
  else setConnectionStep(provider, 'live', 'pending', '尚未验证');

  const cannotUseClaudeCli = provider === 'claude' && result.cliFound === false;
  controls.primary.textContent = presentation.primary.label;
  controls.primary.dataset.action = presentation.primary.action;
  controls.primary.dataset.state = presentation.verdictState;
  controls.primary.disabled = presentation.primary.disabled;
  controls.repair.disabled = busy || !managedInstalled || cannotUseClaudeCli;
  controls.disconnect.disabled = busy || !managedInstalled || cannotUseClaudeCli;
}

async function refreshAgentIntegration(provider) {
  try {
    const result = await window.settingsAPI.getAgentIntegration(provider);
    renderAgentIntegration(provider, result);
    return result;
  } catch (error) {
    const result = { state: 'error', error: error.message };
    renderAgentIntegration(provider, result);
    return result;
  }
}

async function refreshAgentIntegrations() {
  byId('refresh-integrations').disabled = true;
  for (const provider of agentProviders) {
    if (!integrationOperations.has(provider)) renderAgentIntegration(provider, { state: 'checking' });
  }
  await Promise.allSettled(agentProviders.map(refreshAgentIntegration));
  byId('refresh-integrations').disabled = integrationOperations.size > 0;
}

async function pollTerminalOperation(provider, operation) {
  for (let attempt = 0; attempt < 30; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 1000));
    const result = await refreshAgentIntegration(provider);
    if (result.state === 'error') {
      showStatus(`连接操作失败：${result.error}`, true);
      return;
    }
    if (operation === 'disconnect' && result.state === 'not-installed') {
      showStatus('已经断开。重新打开 Claude Code 会话后生效。');
      return;
    }
    if (operation !== 'disconnect' && result.state === 'connected') {
      await testAgentIntegration(provider);
      return;
    }
  }
  showStatus('暂时没有检测到结果。请查看 Terminal 中的信息，再点“重新检测连接状态”。', true);
}

async function manageAgentIntegration(provider, forceRepair = false) {
  if (integrationOperations.has(provider)) return;
  const current = integrationResults[provider] || {};
  const repair = forceRepair;
  const operation = current.state === 'legacy' ? 'migrate' : repair ? 'repair' : 'install';
  integrationOperations.set(provider, operation);
  byId('refresh-integrations').disabled = true;
  renderAgentIntegration(provider, current);
  try {
    const result = repair
      ? await window.settingsAPI.repairAgentIntegration(provider)
      : await window.settingsAPI.installAgentIntegration(provider);
    renderAgentIntegration(provider, result);
    if (result.state === 'opened') {
      showStatus('已打开 Codex 插件页。确认安装后，新开任务并在 /hooks 中审查这个 Hook。');
      return;
    }
    if (result.state === 'terminal-opened') {
      showStatus(result.operation === 'migrate'
        ? '已在 Terminal 中开始升级 Claude Code 旧版插件，完成后这里会自动更新。'
        : '已在 Terminal 中开始操作 Claude Code，完成后这里会自动更新。');
      await pollTerminalOperation(provider, result.operation);
      return;
    }
    await testAgentIntegration(provider);
  } catch (error) {
    renderAgentIntegration(provider, { ...current, state: 'error', error: error.message });
    showStatus(`连接失败：${error.message}`, true);
  } finally {
    integrationOperations.delete(provider);
    byId('refresh-integrations').disabled = integrationOperations.size > 0;
    renderAgentIntegration(provider, integrationResults[provider] || current);
  }
}

async function disconnectAgentIntegration(provider) {
  if (integrationOperations.has(provider)) return;
  const name = provider === 'codex' ? 'Codex' : 'Claude Code';
  if (!window.confirm(`断开水滴鱼与 ${name} 的状态连接？`)) return;
  const current = integrationResults[provider] || {};
  integrationOperations.set(provider, 'disconnect');
  byId('refresh-integrations').disabled = true;
  renderAgentIntegration(provider, current);
  try {
    const result = await window.settingsAPI.disconnectAgentIntegration(provider);
    renderAgentIntegration(provider, result);
    if (result.state === 'opened-disconnect') {
      showStatus('已打开 Codex 插件页。此环境没有 Codex CLI，请在页面里移除水滴鱼插件。');
      return;
    }
    if (result.state === 'terminal-opened') {
      showStatus('已在 Terminal 中开始断开 Claude Code，完成后这里会自动更新。');
      await pollTerminalOperation(provider, 'disconnect');
      return;
    }
    showStatus(`已经断开 ${name}。`);
    await refreshAgentIntegration(provider);
  } catch (error) {
    renderAgentIntegration(provider, { ...current, state: 'error', error: error.message });
    showStatus(`断开失败：${error.message}`, true);
  } finally {
    integrationOperations.delete(provider);
    byId('refresh-integrations').disabled = integrationOperations.size > 0;
    renderAgentIntegration(provider, integrationResults[provider] || current);
  }
}

async function testAgentIntegration(provider) {
  try {
    const result = await window.settingsAPI.testAgentIntegration(provider);
    renderAgentIntegration(provider, result);
    showStatus(provider === 'codex'
      ? '等待真实状态：请新开或继续一个 Codex 任务，并确认 /hooks 已信任。'
      : '等待真实状态：请在新开的 Claude Code 会话里提交一条任务。');
    clearTimeout(connectionTestTimers[provider]);
    connectionTestTimers[provider] = setTimeout(() => refreshAgentIntegration(provider), 61000);
    return result;
  } catch (error) {
    showStatus(`测试失败：${error.message}`, true);
    return null;
  }
}

async function runPrimaryAgentAction(provider) {
  const controls = integrationControls[provider];
  switch (controls.primary.dataset.action) {
    case 'manage':
      await manageAgentIntegration(provider);
      break;
    case 'update':
      await manageAgentIntegration(provider, true);
      break;
    case 'verify':
      await testAgentIntegration(provider);
      break;
    case 'refresh':
      renderAgentIntegration(provider, { state: 'checking' });
      await refreshAgentIntegration(provider);
      break;
    case 'enable': {
      try {
        const result = await window.settingsAPI.setAgentIntegrationReceiving(provider, true);
        renderAgentIntegration(provider, result);
        showStatus('已经恢复接收任务状态。现在可以开始验证连接。');
      } catch (error) {
        showStatus(`恢复接收失败：${error.message}`, true);
      }
      break;
    }
    case 'details':
      controls.details.open = true;
      controls.details.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      showStatus('处理原因已经展开；水滴鱼没有自动删除任何插件。');
      break;
    default:
      break;
  }
}

function renderConfig(config, characters, languages, sounds, accessories) {
  document.querySelectorAll('input[name="workday"]').forEach((input) => {
    input.checked = config.schedule.workdays.includes(Number(input.value));
  });
  setValue('lunch-time', config.schedule.lunchTime);
  setValue('off-work-time', config.schedule.offWorkTime);
  setChecked('lunch-reminder', config.schedule.lunchReminder);
  setChecked('off-work-reminder', config.schedule.offWorkReminder);
  setChecked('half-hour-reminders', config.schedule.halfHourReminders);
  setChecked('workday-greeting-enabled', config.greetings.workday.enabled);
  setValue('workday-greeting-start', config.greetings.workday.start);
  setValue('workday-greeting-end', config.greetings.workday.end);
  setChecked('dayoff-greeting-enabled', config.greetings.dayOff.enabled);
  setValue('dayoff-greeting-start', config.greetings.dayOff.start);
  setValue('dayoff-greeting-end', config.greetings.dayOff.end);
  setChecked('quiet-enabled', config.quietHours.enabled);
  setValue('quiet-start', config.quietHours.start);
  setValue('quiet-end', config.quietHours.end);
  renderCharacters(characters, config.pet.characterPackId);
  renderLanguages(languages, config.language.packId);
  setValue('idle-min', config.language.idleMinMinutes);
  setValue('idle-max', config.language.idleMaxMinutes);
  setChecked('idle-enabled', config.language.idleEnabled);
  setChecked('rare-enabled', config.language.rareEnabled);
  setChecked('category-schedule', config.language.categories.schedule);
  setChecked('category-system', config.language.categories.system);
  setChecked('category-calendar', config.language.categories.calendar);
  setChecked('category-agents', config.language.categories.agents);
  setValue('pet-speed', config.pet.speed);
  speedOutput.value = `${config.pet.speed.toFixed(2)}×`;
  setValue('pet-scale', config.pet.scale);
  scaleOutput.value = `${Math.round(config.pet.scale * 100)}%`;
  setValue('pet-move-axis', config.pet.moveAxis || 'horizontal');
  setChecked('roam-without-tasks', config.pet.roamWhenNoTasks);
  setChecked('launch-at-login', config.startup.launchAtLogin);
  setChecked('integration-codex', config.integrations.codex);
  setChecked('integration-claude', config.integrations.claudeCode);
  setChecked('integration-calendar', config.integrations.calendar);
  setChecked('privacy-task-titles', config.privacy.includeTaskTitles);
  setChecked('privacy-calendar-titles', config.privacy.includeCalendarTitles);
  const soundSetting = config.sound?.taskComplete || { enabled: true, soundId: '' };
  renderSounds(sounds || [], soundSetting.soundId);
  setChecked('sound-task-complete-enabled', soundSetting.enabled);
  diyMap = JSON.parse(JSON.stringify(config.pet.customization || {}));
  accessoryMap = JSON.parse(JSON.stringify(config.pet.accessories || {}));
  accessoryCatalog = Array.isArray(accessories) ? accessories : accessoryCatalog;
  loadDiy(config.pet.characterPackId);
  syncDependentControls();
  updateFormValidity();
}

function readConfig() {
  return {
    version: 1,
    schedule: {
      workdays: [...document.querySelectorAll('input[name="workday"]:checked')].map((input) => Number(input.value)),
      lunchTime: byId('lunch-time').value,
      offWorkTime: byId('off-work-time').value,
      lunchReminder: byId('lunch-reminder').checked,
      offWorkReminder: byId('off-work-reminder').checked,
      halfHourReminders: byId('half-hour-reminders').checked,
    },
    greetings: {
      workday: {
        enabled: byId('workday-greeting-enabled').checked,
        start: byId('workday-greeting-start').value || '07:00',
        end: byId('workday-greeting-end').value || '11:00',
      },
      dayOff: {
        enabled: byId('dayoff-greeting-enabled').checked,
        start: byId('dayoff-greeting-start').value || '07:00',
        end: byId('dayoff-greeting-end').value || '18:00',
      },
    },
    quietHours: {
      enabled: byId('quiet-enabled').checked,
      start: byId('quiet-start').value || '22:30',
      end: byId('quiet-end').value || '08:30',
    },
    language: {
      packId: byId('language-pack').value,
      idleEnabled: byId('idle-enabled').checked,
      rareEnabled: byId('rare-enabled').checked,
      idleMinMinutes: Number(byId('idle-min').value || 12),
      idleMaxMinutes: Number(byId('idle-max').value || 35),
      categories: {
        schedule: byId('category-schedule').checked,
        system: byId('category-system').checked,
        calendar: byId('category-calendar').checked,
        agents: byId('category-agents').checked,
      },
    },
    pet: {
      characterPackId: byId('character-pack').value,
      speed: Number(speedInput.value),
      scale: Number(scaleInput.value),
      roamWhenNoTasks: byId('roam-without-tasks').checked,
      moveAxis: byId('pet-move-axis').value,
      customization: diyMap,
      accessories: accessoryMap,
    },
    startup: {
      launchAtLogin: byId('launch-at-login').checked,
    },
    integrations: {
      codex: byId('integration-codex').checked,
      claudeCode: byId('integration-claude').checked,
      calendar: byId('integration-calendar').checked,
    },
    privacy: {
      includeTaskTitles: byId('privacy-task-titles').checked,
      includeCalendarTitles: byId('privacy-calendar-titles').checked,
    },
    sound: {
      taskComplete: {
        enabled: byId('sound-task-complete-enabled').checked,
        soundId: byId('sound-task-complete-id').value,
      },
    },
  };
}

speedInput.addEventListener('input', () => {
  speedOutput.value = `${Number(speedInput.value).toFixed(2)}×`;
});

scaleInput.addEventListener('input', () => {
  scaleOutput.value = `${Math.round(Number(scaleInput.value) * 100)}%`;
});

for (const tab of panelTabs) {
  tab.addEventListener('click', () => activatePanel(tab.dataset.panel));
  tab.addEventListener('keydown', (event) => {
    if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault();
    const current = panelTabs.indexOf(tab);
    const nextIndex = event.key === 'Home'
      ? 0
      : event.key === 'End'
        ? panelTabs.length - 1
        : (current + (event.key === 'ArrowDown' ? 1 : -1) + panelTabs.length) % panelTabs.length;
    activatePanel(panelTabs[nextIndex].dataset.panel, { focus: true });
  });
}

for (const toggleId of ['workday-greeting-enabled', 'dayoff-greeting-enabled', 'quiet-enabled', 'idle-enabled', 'sound-task-complete-enabled']) {
  byId(toggleId).addEventListener('change', syncDependentControls);
}

byId('sound-preview-button').addEventListener('click', async () => {
  const soundId = byId('sound-task-complete-id').value;
  if (!soundId) return;
  const button = byId('sound-preview-button');
  button.disabled = true;
  try {
    await window.settingsAPI.previewSound(soundId);
  } finally {
    setTimeout(() => { button.disabled = false; }, 350);
  }
});

for (const inputId of [
  'workday-greeting-start',
  'workday-greeting-end',
  'dayoff-greeting-start',
  'dayoff-greeting-end',
  'idle-min',
  'idle-max',
]) {
  byId(inputId).addEventListener('input', updateFormValidity);
}

byId('character-pack').addEventListener('change', (event) => {
  const languagePackId = event.target.selectedOptions[0]?.dataset.defaultLanguagePack;
  if (languagePackId && [...byId('language-pack').options].some((option) => option.value === languagePackId)) {
    setValue('language-pack', languagePackId);
  }
  applyCharacterCopy(event.target.value);
  loadDiy(event.target.value);
});

byId('diy-reset').addEventListener('click', () => {
  const packId = byId('character-pack').value;
  diyMap[packId] = diyModel.defaultDiy();
  accessoryMap[packId] = accessoryModel.defaultAccessories();
  renderDiyControls();
  renderAccessoryControls();
  renderDiyPreview();
});

for (const provider of agentProviders) {
  integrationControls[provider].primary.addEventListener('click', () => runPrimaryAgentAction(provider));
  integrationControls[provider].repair.addEventListener('click', () => manageAgentIntegration(provider, true));
  integrationControls[provider].disconnect.addEventListener('click', () => disconnectAgentIntegration(provider));
}
byId('refresh-integrations').addEventListener('click', refreshAgentIntegrations);

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!validateVisibleForm()) {
    showStatus('有一项时间设置需要修改。', true);
    return;
  }
  setBusy(true);
  try {
    const result = await window.settingsAPI.save(readConfig());
    renderAppVersion(result.appVersion);
    renderConfig(result.config, result.characters, result.languages, result.taskCompleteSounds, result.accessories);
    renderIntegrationStatus(result.integrationStatus);
    refreshAgentIntegrations();
    showStatus(activeSettingsCopy?.savedStatus || '已保存。');
  } catch (error) {
    showStatus(`保存失败：${error.message}`, true);
  } finally {
    setBusy(false);
  }
});

resetButton.addEventListener('click', async () => {
  if (!window.confirm('恢复所有默认设置？')) return;
  setBusy(true);
  try {
    const result = await window.settingsAPI.reset();
    renderAppVersion(result.appVersion);
    renderConfig(result.config, result.characters, result.languages, result.taskCompleteSounds, result.accessories);
    renderIntegrationStatus(result.integrationStatus);
    showStatus(activeSettingsCopy?.resetStatus || '已经恢复默认。');
  } catch (error) {
    showStatus(`恢复失败：${error.message}`, true);
  } finally {
    setBusy(false);
  }
});

window.settingsAPI.load()
  .then((result) => {
    renderAppVersion(result.appVersion);
    renderConfig(result.config, result.characters, result.languages, result.taskCompleteSounds, result.accessories);
    renderIntegrationStatus(result.integrationStatus);
    refreshAgentIntegrations();
    if (result.warning) showStatus(result.warning, true);
  })
  .catch((error) => showStatus(`读取设置失败：${error.message}`, true));

window.settingsAPI.onIntegrationStatus((integrationStatus) => renderIntegrationStatus(integrationStatus));
window.settingsAPI.onAgentConnectionHealth((health) => {
  const current = integrationResults[health.provider] || { state: 'checking' };
  const testPassed = current.health === 'awaiting-event' && health.health === 'active';
  refreshAgentIntegration(health.provider).then((result) => {
    const usable = result.state === 'connected' || result.state === 'cli-missing';
    if (testPassed && usable && result.receiveEnabled !== false) {
      showStatus('连接测试通过。鱼已经收到真实任务状态。');
    }
  });
});
window.settingsAPI.onSettingChanged((setting) => {
  if (setting?.path === 'pet.roamWhenNoTasks' && typeof setting.value === 'boolean') {
    setChecked('roam-without-tasks', setting.value);
  }
});
