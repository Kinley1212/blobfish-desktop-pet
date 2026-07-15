const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('petAPI', {
  getCharacterPack: () => ipcRenderer.invoke('character-pack:get'),
  onDirection: (callback) => ipcRenderer.on('direction', (_event, dir) => callback(dir)),
  onReminder: (callback) => ipcRenderer.on('reminder', (_event, text) => callback(text)),
  onBump: (callback) => ipcRenderer.on('bump', () => callback()),
  onCheckHover: (callback) => ipcRenderer.on('check-hover', (_event, x, y) => callback(x, y)),
  setPaused: (value) => ipcRenderer.send('pause', value),
  setIgnoreMouse: (ignore) => ipcRenderer.send('set-ignore-mouse', ignore),
  dragStart: () => ipcRenderer.send('drag-start'),
  dragMove: (dx, dy) => ipcRenderer.send('drag-move', dx, dy),
  dragEnd: (vx, vy) => ipcRenderer.send('drag-end', vx, vy),
});
