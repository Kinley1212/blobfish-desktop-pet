const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('petAPI', {
  getCharacterPack: () => ipcRenderer.invoke('character-pack:get'),
  getPetConfig: () => ipcRenderer.invoke('pet-config:get'),
  getAgentState: () => ipcRenderer.invoke('agent-state:get'),
  onDirection: (callback) => ipcRenderer.on('direction', (_event, dir) => callback(dir)),
  onSpeech: (callback) => ipcRenderer.on('speech', (_event, message) => callback(message)),
  onAgentState: (callback) => ipcRenderer.on('agent-state', (_event, state) => callback(state)),
  onPetConfig: (callback) => ipcRenderer.on('pet-config', (_event, config) => callback(config)),
  onBump: (callback) => ipcRenderer.on('bump', () => callback()),
  onCheckHover: (callback) => ipcRenderer.on('check-hover', (_event, x, y) => callback(x, y)),
  setPaused: (value) => ipcRenderer.send('pause', value),
  petClicked: () => ipcRenderer.send('pet-clicked'),
  setIgnoreMouse: (ignore) => ipcRenderer.send('set-ignore-mouse', ignore),
  dragStart: () => ipcRenderer.send('drag-start'),
  dragMove: (dx, dy) => ipcRenderer.send('drag-move', dx, dy),
  dragEnd: (vx, vy) => ipcRenderer.send('drag-end', vx, vy),
});
