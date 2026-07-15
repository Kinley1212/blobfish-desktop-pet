const form = document.getElementById('settings-form');
const status = document.getElementById('status');
const saveButton = form.querySelector('button[type="submit"]');
const resetButton = document.getElementById('reset-button');
const speedInput = document.getElementById('pet-speed');
const speedOutput = document.getElementById('speed-output');

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
  setChecked('stop-all-complete', config.pet.stopWhenAllTasksComplete);
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
      stopWhenAllTasksComplete: byId('stop-all-complete').checked,
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

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  setBusy(true);
  try {
    const result = await window.settingsAPI.save(readConfig());
    renderConfig(result.config, result.languages);
    renderIntegrationStatus(result.integrationStatus);
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
    if (result.warning) showStatus(result.warning, true);
  })
  .catch((error) => showStatus(`读取设置失败：${error.message}`, true));

window.settingsAPI.onIntegrationStatus((integrationStatus) => renderIntegrationStatus(integrationStatus));
