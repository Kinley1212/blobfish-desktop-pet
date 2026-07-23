const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('settingsAPI', {
  load: () => ipcRenderer.invoke('settings:get'),
  save: (config) => ipcRenderer.invoke('settings:save', config),
  reset: () => ipcRenderer.invoke('settings:reset'),
  previewSound: (soundId) => ipcRenderer.invoke('settings:preview-sound', soundId),
  getCharacterArt: (packId) => ipcRenderer.invoke('settings:character-art', packId),
  getAgentIntegration: (provider) => ipcRenderer.invoke('agent-integrations:inspect', provider),
  installAgentIntegration: (provider) => ipcRenderer.invoke('agent-integrations:install', provider),
  repairAgentIntegration: (provider) => ipcRenderer.invoke('agent-integrations:repair', provider),
  disconnectAgentIntegration: (provider) => ipcRenderer.invoke('agent-integrations:disconnect', provider),
  testAgentIntegration: (provider) => ipcRenderer.invoke('agent-integrations:test', provider),
  setAgentIntegrationReceiving: (provider, enabled) => ipcRenderer.invoke('agent-integrations:set-receiving', provider, enabled),
  onIntegrationStatus: (callback) => ipcRenderer.on('integration-status', (_event, status) => callback(status)),
  onAgentConnectionHealth: (callback) => ipcRenderer.on('agent-connection-health', (_event, health) => callback(health)),
  onSettingChanged: (callback) => ipcRenderer.on('setting-changed', (_event, setting) => callback(setting)),
});
