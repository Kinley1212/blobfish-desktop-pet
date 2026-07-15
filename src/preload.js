const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('petAPI', {
  getCharacterPack: () => ipcRenderer.invoke('character-pack:get'),
  onDirection: (callback) => ipcRenderer.on('direction', (_event, dir) => callback(dir)),
  onSpeech: (callback) => ipcRenderer.on('speech', (_event, message) => callback(message)),
  onBump: (callback) => ipcRenderer.on('bump', () => callback()),
  onCheckHover: (callback) => ipcRenderer.on('check-hover', (_event, x, y) => callback(x, y)),
  setPaused: (value) => ipcRenderer.send('pause', value),
  petClicked: () => ipcRenderer.send('pet-clicked'),
  setIgnoreMouse: (ignore) => ipcRenderer.send('set-ignore-mouse', ignore),
  dragStart: () => ipcRenderer.send('drag-start'),
  dragMove: (dx, dy) => ipcRenderer.send('drag-move', dx, dy),
  dragEnd: (vx, vy) => ipcRenderer.send('drag-end', vx, vy),
});
