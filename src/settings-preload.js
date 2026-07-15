const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('settingsAPI', {
  load: () => ipcRenderer.invoke('settings:get'),
  save: (config) => ipcRenderer.invoke('settings:save', config),
  reset: () => ipcRenderer.invoke('settings:reset'),
  getAgentIntegrations: () => ipcRenderer.invoke('agent-integrations:get'),
  installAgentIntegration: (provider) => ipcRenderer.invoke('agent-integrations:install', provider),
  onIntegrationStatus: (callback) => ipcRenderer.on('integration-status', (_event, status) => callback(status)),
});
