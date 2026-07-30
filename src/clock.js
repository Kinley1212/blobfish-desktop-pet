const byId = (id) => document.getElementById(id);
const uiI18n = globalThis.uiI18n;
const state = {
  payload: null,
  editingAlarmId: null,
  messageTimer: null,
  uiLocale: uiI18n.DEFAULT_LOCALE,
};
const tr = (key) => uiI18n.t(state.uiLocale, key);

function pad(value) {
  return String(value).padStart(2, '0');
}

function localDateKey(date) {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function formatDuration(milliseconds) {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  if (hours) return `${hours}:${pad(minutes)}:${pad(seconds)}`;
  return `${pad(minutes)}:${pad(seconds)}`;
}

function showMessage(text, tone = 'error') {
  clearTimeout(state.messageTimer);
  const node = byId('message');
  node.textContent = text;
  node.dataset.visible = 'true';
  node.dataset.tone = tone;
  state.messageTimer = setTimeout(() => {
    node.dataset.visible = 'false';
  }, 4500);
}

async function run(operation, successMessage) {
  try {
    const payload = await operation();
    if (payload) applyPayload(payload);
    if (successMessage) showMessage(successMessage, 'success');
    return payload;
  } catch (error) {
    showMessage(error.message || (state.uiLocale === 'en' ? 'That could not be saved.' : '刚才没有设置成功。'));
    return null;
  }
}

function populateSoundOptions() {
  for (const select of [byId('alarm-sound'), byId('timer-sound')]) {
    select.replaceChildren();
    for (const sound of state.payload.sounds) {
      const option = document.createElement('option');
      option.value = sound.id;
      option.textContent = sound.label;
      select.append(option);
    }
  }
}

function activeTimerRemaining(timer) {
  return timer.state === 'running' ? timer.dueAtMs - Date.now() : timer.remainingMs;
}

function renderTimer() {
  const timer = state.payload.state.timer;
  byId('active-timer').hidden = !timer;
  byId('timer-starter').hidden = Boolean(timer);
  byId('timer-state').textContent = timer
    ? (timer.state === 'running' ? tr('正在计时') : tr('已暂停'))
    : tr('还没有开始');
  if (!timer) return;
  byId('timer-label').textContent = timer.label || tr('计时中');
  byId('timer-countdown').textContent = formatDuration(activeTimerRemaining(timer));
  byId('toggle-timer').textContent = timer.state === 'running' ? tr('暂停') : tr('继续');
}

function alarmRepeatLabel(alarm) {
  if (alarm.mode === 'once') return alarm.date;
  if (alarm.mode === 'daily') return tr('每天');
  if (alarm.mode === 'workdays') return tr('工作日');
  const names = state.uiLocale === 'en'
    ? ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
    : ['日', '一', '二', '三', '四', '五', '六'];
  return state.uiLocale === 'en'
    ? alarm.weekdays.map((day) => names[day]).join(', ')
    : `周${alarm.weekdays.map((day) => names[day]).join('、')}`;
}

function nextAlarmTime(alarm) {
  if (alarm.mode === 'once') return `${alarm.date} ${alarm.time}`;
  return `${alarmRepeatLabel(alarm)} ${alarm.time}`;
}

function renderAlarmList() {
  const list = byId('alarm-list');
  list.replaceChildren();
  const alarms = state.payload.state.alarms;
  byId('alarm-count').textContent = state.uiLocale === 'en'
    ? `${alarms.length} ${alarms.length === 1 ? 'alarm' : 'alarms'}`
    : `${alarms.length} 个`;
  byId('alarm-empty').hidden = alarms.length > 0;

  for (const alarm of alarms) {
    const item = document.createElement('div');
    item.className = 'alarm-item';

    const enabled = document.createElement('input');
    enabled.type = 'checkbox';
    enabled.className = 'alarm-enable';
    enabled.checked = alarm.enabled;
    enabled.setAttribute('aria-label', state.uiLocale === 'en'
      ? `Enable ${alarm.label || alarm.time}`
      : `${alarm.label || alarm.time}启用状态`);
    enabled.addEventListener('change', () => {
      void run(() => window.clockAPI.updateAlarm(alarm.id, { enabled: enabled.checked }));
    });

    const meta = document.createElement('div');
    meta.className = 'alarm-meta';
    const time = document.createElement('strong');
    time.className = 'alarm-clock-time';
    time.textContent = alarm.time;
    const label = document.createElement('small');
    label.textContent = `${alarm.label || (state.uiLocale === 'en' ? 'Alarm' : '闹钟')} · ${alarmRepeatLabel(alarm)}`;
    meta.append(time, label);

    const actions = document.createElement('div');
    actions.className = 'alarm-actions';
    const edit = document.createElement('button');
    edit.type = 'button';
    edit.className = 'ghost';
    edit.textContent = state.uiLocale === 'en' ? 'Edit' : '编辑';
    edit.addEventListener('click', () => beginAlarmEdit(alarm));
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'ghost danger';
    remove.textContent = state.uiLocale === 'en' ? 'Delete' : '删除';
    remove.addEventListener('click', () => {
      if (!window.confirm(state.uiLocale === 'en'
        ? `Delete “${alarm.label || nextAlarmTime(alarm)}”?`
        : `删除“${alarm.label || nextAlarmTime(alarm)}”？`)) return;
      void run(
        () => window.clockAPI.deleteAlarm(alarm.id),
        state.uiLocale === 'en' ? 'Alarm deleted.' : '闹钟已删除。',
      );
    });
    actions.append(edit, remove);
    item.append(enabled, meta, actions);
    list.append(item);
  }
}

function renderAlerts() {
  const alert = state.payload.state.alerts.find((candidate) => candidate.state === 'ringing');
  byId('ringing-card').hidden = !alert;
  if (!alert) return;
  byId('ringing-kind').textContent = alert.sourceType === 'alarm' ? tr('闹钟到了') : tr('计时结束');
  byId('ringing-title').textContent = alert.label || tr('时间到了');
  byId('snooze-alert').dataset.alertId = alert.id;
  byId('dismiss-alert').dataset.alertId = alert.id;
}

function renderPreferences() {
  const preferences = state.payload.state.preferences;
  byId('alarm-sound-enabled').checked = preferences.alarmSound.enabled;
  byId('alarm-sound').value = preferences.alarmSound.soundId;
  byId('alarm-sound').disabled = !preferences.alarmSound.enabled;
  byId('timer-sound-enabled').checked = preferences.timerSound.enabled;
  byId('timer-sound').value = preferences.timerSound.soundId;
  byId('timer-sound').disabled = !preferences.timerSound.enabled;
  byId('clock-quiet-sound').checked = preferences.allowSoundDuringQuietHours;
}

function applyPayload(payload) {
  const first = !state.payload;
  state.payload = payload;
  state.uiLocale = uiI18n.applyDocument(document, payload.uiLocale);
  if (first) populateSoundOptions();
  renderTimer();
  renderAlarmList();
  renderAlerts();
  renderPreferences();
}

function syncAlarmFields() {
  const mode = byId('alarm-repeat').value;
  byId('alarm-date-row').hidden = mode !== 'once';
  byId('alarm-date').required = mode === 'once';
  byId('weekday-row').hidden = mode !== 'weekly';
}

function resetAlarmForm() {
  state.editingAlarmId = null;
  byId('alarm-name').value = '';
  byId('alarm-repeat').value = 'once';
  byId('alarm-date').value = localDateKey(new Date());
  for (const checkbox of byId('weekday-row').querySelectorAll('input')) checkbox.checked = false;
  byId('save-alarm').textContent = tr('设置闹钟');
  byId('cancel-alarm-edit').hidden = true;
  syncAlarmFields();
}

function beginAlarmEdit(alarm) {
  state.editingAlarmId = alarm.id;
  byId('alarm-time').value = alarm.time;
  byId('alarm-name').value = alarm.label;
  byId('alarm-repeat').value = alarm.mode;
  byId('alarm-date').value = alarm.date || localDateKey(new Date());
  for (const checkbox of byId('weekday-row').querySelectorAll('input')) {
    checkbox.checked = alarm.weekdays.includes(Number(checkbox.value));
  }
  byId('save-alarm').textContent = state.uiLocale === 'en' ? 'Save changes' : '保存修改';
  byId('cancel-alarm-edit').hidden = false;
  syncAlarmFields();
  byId('alarm-time').focus();
}

function alarmFormValue() {
  const mode = byId('alarm-repeat').value;
  const weekdays = [...byId('weekday-row').querySelectorAll('input:checked')]
    .map((checkbox) => Number(checkbox.value));
  if (mode === 'weekly' && weekdays.length === 0) {
    throw new Error(state.uiLocale === 'en' ? 'Select at least one weekday' : '请至少选择一个星期');
  }
  return {
    label: byId('alarm-name').value,
    time: byId('alarm-time').value,
    mode,
    date: mode === 'once' ? byId('alarm-date').value : null,
    weekdays: mode === 'weekly' ? weekdays : [],
  };
}

async function savePreferences() {
  return run(() => window.clockAPI.updatePreferences({
    alarmSound: {
      enabled: byId('alarm-sound-enabled').checked,
      soundId: byId('alarm-sound').value,
    },
    timerSound: {
      enabled: byId('timer-sound-enabled').checked,
      soundId: byId('timer-sound').value,
    },
    allowSoundDuringQuietHours: byId('clock-quiet-sound').checked,
  }));
}

function setInitialDateAndTime() {
  const next = new Date(Date.now() + 60 * 60 * 1000);
  next.setMinutes(0, 0, 0);
  byId('alarm-time').value = `${pad(next.getHours())}:${pad(next.getMinutes())}`;
  byId('alarm-date').value = localDateKey(next);
}

document.querySelectorAll('[data-quick-minutes]').forEach((button) => {
  button.addEventListener('click', () => {
    const durationMinutes = Number(button.dataset.quickMinutes);
    void run(() => window.clockAPI.startTimer({
      durationMinutes,
      label: durationMinutes === 25 ? (state.uiLocale === 'en' ? 'Focus' : '专注') : '',
    }), state.uiLocale === 'en' ? 'Timer started.' : '计时开始。');
  });
});

byId('timer-form').addEventListener('submit', (event) => {
  event.preventDefault();
  void run(() => window.clockAPI.startTimer({
    durationMinutes: Number(byId('timer-minutes').value),
    label: byId('timer-name').value,
  }), state.uiLocale === 'en' ? 'Timer started.' : '计时开始。');
});

byId('toggle-timer').addEventListener('click', () => {
  const timer = state.payload.state.timer;
  if (!timer) return;
  void run(
    () => (timer.state === 'running' ? window.clockAPI.pauseTimer() : window.clockAPI.resumeTimer()),
    timer.state === 'running'
      ? (state.uiLocale === 'en' ? 'Timer paused.' : '计时已暂停。')
      : (state.uiLocale === 'en' ? 'Timer resumed.' : '继续计时。'),
  );
});
byId('extend-timer').addEventListener('click', () => {
  void run(() => window.clockAPI.extendTimer(5), state.uiLocale === 'en' ? 'Added 5 minutes.' : '增加了 5 分钟。');
});
byId('cancel-timer').addEventListener('click', () => {
  void run(() => window.clockAPI.cancelTimer(), state.uiLocale === 'en' ? 'Timer cancelled.' : '计时已取消。');
});

byId('alarm-repeat').addEventListener('change', syncAlarmFields);
byId('cancel-alarm-edit').addEventListener('click', resetAlarmForm);
byId('alarm-form').addEventListener('submit', (event) => {
  event.preventDefault();
  let input;
  try {
    input = alarmFormValue();
  } catch (error) {
    showMessage(error.message);
    return;
  }
  const editingId = state.editingAlarmId;
  void run(
    () => (editingId
      ? window.clockAPI.updateAlarm(editingId, input)
      : window.clockAPI.createAlarm(input)),
    editingId
      ? (state.uiLocale === 'en' ? 'Alarm updated.' : '闹钟已更新。')
      : (state.uiLocale === 'en' ? 'Alarm set.' : '闹钟设置好了。'),
  ).then((payload) => {
    if (payload) resetAlarmForm();
  });
});

byId('snooze-alert').addEventListener('click', () => {
  const id = byId('snooze-alert').dataset.alertId;
  if (id) void run(
    () => window.clockAPI.snoozeAlert(id, 5),
    state.uiLocale === 'en' ? 'Will remind you again in 5 minutes.' : '五分钟后再提醒。',
  );
});
byId('dismiss-alert').addEventListener('click', () => {
  const id = byId('dismiss-alert').dataset.alertId;
  if (id) void run(
    () => window.clockAPI.dismissAlert(id),
    state.uiLocale === 'en' ? 'Alert dismissed.' : '提醒已关闭。',
  );
});

for (const id of ['alarm-sound-enabled', 'alarm-sound', 'timer-sound-enabled', 'timer-sound', 'clock-quiet-sound']) {
  byId(id).addEventListener('change', () => { void savePreferences(); });
}
byId('preview-alarm-sound').addEventListener('click', () => {
  void run(() => window.clockAPI.previewSound(byId('alarm-sound').value));
});
byId('preview-timer-sound').addEventListener('click', () => {
  void run(() => window.clockAPI.previewSound(byId('timer-sound').value));
});

window.clockAPI.onState((payload) => applyPayload(payload));

setInitialDateAndTime();
syncAlarmFields();
setInterval(renderTimer, 1000);
void run(() => window.clockAPI.load());
