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

function byId(id) { return document.getElementById(id); }
function setChecked(id, value) { byId(id).checked = value; }
function setValue(id, value) { byId(id).value = value; }

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
    listening: '已在本机监听',
    stopped: '未启动',
    error: '启动失败，请查看日志',
  };
  const bridgeStatus = integrationStatus.agentBridge || 'stopped';
  byId('agent-bridge-status').textContent = `任务桥接：${bridgeLabels[bridgeStatus] || bridgeLabels.error}`;
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
  const live = health === 'active';
  const busy = ['checking', 'opened', 'opened-disconnect', 'terminal-opened'].includes(result.state);
  const managedInstalled = result.state === 'connected' || result.state === 'disabled' || live;
  const presentation = window.integrationUI.describeAgentIntegration(provider, result, {
    lastEventLabel: formatLastEvent(result.lastEventAt),
  });

  statusElement.textContent = presentation.summary;
  statusElement.classList.toggle('error', ['error', 'conflict'].includes(result.state) || health === 'test-timeout');
  verdictElement.textContent = presentation.verdict;
  verdictElement.dataset.state = presentation.verdictState;
  byId(`${provider}-next-step`).textContent = presentation.instruction;
  technicalDetails.textContent = [
    result.pluginId ? `插件：${result.pluginId}` : null,
    result.version ? `版本：${result.version}` : null,
    result.error ? `详情：${result.error}` : null,
  ].filter(Boolean).join(' · ') || '未检测到插件标识。';

  if (result.state === 'checking') setConnectionStep(provider, 'cli', 'pending', '正在检测…');
  else if (result.cliFound) setConnectionStep(provider, 'cli', 'done', '已找到命令行工具');
  else if (result.state === 'opened' || result.state === 'opened-disconnect') setConnectionStep(provider, 'cli', 'active', '已打开 Codex App 插件页');
  else if (live) setConnectionStep(provider, 'cli', 'done', '已由真实任务事件确认');
  else setConnectionStep(provider, 'cli', 'error', '未找到命令行工具');

  if (live) setConnectionStep(provider, 'plugin', 'done', '插件正在发送状态');
  else if (result.state === 'connected') setConnectionStep(provider, 'plugin', 'done', result.version ? `已安装 v${result.version}` : '已安装并启用');
  else if (result.state === 'legacy') setConnectionStep(provider, 'plugin', 'active', result.version ? `检测到旧版 v${result.version}` : '检测到可升级的旧版');
  else if (result.state === 'disabled') setConnectionStep(provider, 'plugin', 'error', '已安装，但被停用');
  else if (result.state === 'conflict') setConnectionStep(provider, 'plugin', 'error', '同名插件来源冲突');
  else if (result.state === 'error') setConnectionStep(provider, 'plugin', 'error', '检测或操作失败');
  else if (result.state === 'opened' || result.state === 'terminal-opened') setConnectionStep(provider, 'plugin', 'active', '等待安装结果');
  else if (result.state === 'opened-disconnect') setConnectionStep(provider, 'plugin', 'active', '等待手动移除');
  else setConnectionStep(provider, 'plugin', 'pending', '尚未安装');

  if (live) setConnectionStep(provider, 'live', 'done', `最近收到：${formatLastEvent(result.lastEventAt)}`);
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
  for (const provider of agentProviders) renderAgentIntegration(provider, { state: 'checking' });
  await Promise.allSettled(agentProviders.map(refreshAgentIntegration));
  byId('refresh-integrations').disabled = false;
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
  const current = integrationResults[provider] || {};
  const repair = forceRepair;
  const operation = current.state === 'legacy' ? 'migrate' : repair ? 'repair' : 'install';
  renderAgentIntegration(provider, { ...current, state: 'terminal-opened', operation });
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
  }
}

async function disconnectAgentIntegration(provider) {
  const name = provider === 'codex' ? 'Codex' : 'Claude Code';
  if (!window.confirm(`断开水滴鱼与 ${name} 的状态连接？`)) return;
  const current = integrationResults[provider] || {};
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
    case 'verify':
      await testAgentIntegration(provider);
      break;
    case 'refresh':
      renderAgentIntegration(provider, { state: 'checking' });
      await refreshAgentIntegration(provider);
      break;
    case 'details':
      controls.details.open = true;
      controls.details.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      showStatus('处理原因已经展开；水滴鱼没有自动删除任何插件。');
      break;
    default:
      break;
  }
}

function renderConfig(config, languages) {
  document.querySelectorAll('input[name="workday"]').forEach((input) => {
    input.checked = config.schedule.workdays.includes(Number(input.value));
  });
  setValue('lunch-time', config.schedule.lunchTime);
  setValue('off-work-time', config.schedule.offWorkTime);
  setChecked('lunch-reminder', config.schedule.lunchReminder);
  setChecked('off-work-reminder', config.schedule.offWorkReminder);
  setChecked('half-hour-reminders', config.schedule.halfHourReminders);
  setChecked('quiet-enabled', config.quietHours.enabled);
  setValue('quiet-start', config.quietHours.start);
  setValue('quiet-end', config.quietHours.end);
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
  setChecked('roam-without-tasks', config.pet.roamWhenNoTasks);
  setChecked('launch-at-login', config.startup.launchAtLogin);
  setChecked('integration-codex', config.integrations.codex);
  setChecked('integration-claude', config.integrations.claudeCode);
  setChecked('integration-calendar', config.integrations.calendar);
  setChecked('privacy-task-titles', config.privacy.includeTaskTitles);
  setChecked('privacy-calendar-titles', config.privacy.includeCalendarTitles);
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
    quietHours: {
      enabled: byId('quiet-enabled').checked,
      start: byId('quiet-start').value,
      end: byId('quiet-end').value,
    },
    language: {
      packId: byId('language-pack').value,
      idleEnabled: byId('idle-enabled').checked,
      rareEnabled: byId('rare-enabled').checked,
      idleMinMinutes: Number(byId('idle-min').value),
      idleMaxMinutes: Number(byId('idle-max').value),
      categories: {
        schedule: byId('category-schedule').checked,
        system: byId('category-system').checked,
        calendar: byId('category-calendar').checked,
        agents: byId('category-agents').checked,
      },
    },
    pet: {
      speed: Number(speedInput.value),
      scale: Number(scaleInput.value),
      roamWhenNoTasks: byId('roam-without-tasks').checked,
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
  };
}

speedInput.addEventListener('input', () => {
  speedOutput.value = `${Number(speedInput.value).toFixed(2)}×`;
});

scaleInput.addEventListener('input', () => {
  scaleOutput.value = `${Math.round(Number(scaleInput.value) * 100)}%`;
});

for (const provider of agentProviders) {
  integrationControls[provider].primary.addEventListener('click', () => runPrimaryAgentAction(provider));
  integrationControls[provider].repair.addEventListener('click', () => manageAgentIntegration(provider, true));
  integrationControls[provider].disconnect.addEventListener('click', () => disconnectAgentIntegration(provider));
}
byId('refresh-integrations').addEventListener('click', refreshAgentIntegrations);

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  setBusy(true);
  try {
    const result = await window.settingsAPI.save(readConfig());
    renderConfig(result.config, result.languages);
    renderIntegrationStatus(result.integrationStatus);
    refreshAgentIntegrations();
    showStatus('已保存。鱼知道了。');
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
    renderConfig(result.config, result.languages);
    renderIntegrationStatus(result.integrationStatus);
    showStatus('已经恢复默认。');
  } catch (error) {
    showStatus(`恢复失败：${error.message}`, true);
  } finally {
    setBusy(false);
  }
});

window.settingsAPI.load()
  .then((result) => {
    renderConfig(result.config, result.languages);
    renderIntegrationStatus(result.integrationStatus);
    refreshAgentIntegrations();
    if (result.warning) showStatus(result.warning, true);
  })
  .catch((error) => showStatus(`读取设置失败：${error.message}`, true));

window.settingsAPI.onIntegrationStatus((integrationStatus) => renderIntegrationStatus(integrationStatus));
window.settingsAPI.onAgentConnectionHealth((health) => {
  const current = integrationResults[health.provider] || { state: 'checking' };
  const testPassed = current.health === 'awaiting-event' && health.health === 'active';
  renderAgentIntegration(health.provider, { ...current, ...health });
  if (testPassed) showStatus('连接测试通过。鱼已经收到真实任务状态。');
});
