const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('dialogueAPI', {
  getPack: () => ipcRenderer.invoke('dialogue:get'),
  getCharacter: () => ipcRenderer.invoke('dialogue:character'),
  react: (reaction) => ipcRenderer.send('dialogue:react', reaction),
  close: () => ipcRenderer.send('dialogue:close'),
});
