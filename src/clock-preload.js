const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('clockAPI', {
  load: () => ipcRenderer.invoke('clock:get'),
  createAlarm: (input) => ipcRenderer.invoke('clock:alarm-create', input),
  updateAlarm: (id, patch) => ipcRenderer.invoke('clock:alarm-update', id, patch),
  deleteAlarm: (id) => ipcRenderer.invoke('clock:alarm-delete', id),
  startTimer: (input) => ipcRenderer.invoke('clock:timer-start', input),
  pauseTimer: () => ipcRenderer.invoke('clock:timer-pause'),
  resumeTimer: () => ipcRenderer.invoke('clock:timer-resume'),
  extendTimer: (minutes) => ipcRenderer.invoke('clock:timer-extend', minutes),
  cancelTimer: () => ipcRenderer.invoke('clock:timer-cancel'),
  snoozeAlert: (id, minutes) => ipcRenderer.invoke('clock:alert-snooze', id, minutes),
  dismissAlert: (id) => ipcRenderer.invoke('clock:alert-dismiss', id),
  updatePreferences: (preferences) => ipcRenderer.invoke('clock:preferences-update', preferences),
  previewSound: (soundId) => ipcRenderer.invoke('clock:preview-sound', soundId),
  onState: (callback) => ipcRenderer.on('clock-state', (_event, payload) => callback(payload)),
});
