// Local QA only: a separate Electron host for the packaged Autocomplete Everywhere helper.
const { app, BrowserWindow } = require('electron');
const path = require('node:path');
app.setName('Autocomplete Everywhere Context Lab');
app.whenReady().then(() => {
  const window = new BrowserWindow({
    width: 960, height: 740, title: 'Autocomplete Everywhere Context Lab',
    webPreferences: { contextIsolation: true, nodeIntegration: false },
  });
  window.loadFile(path.join(__dirname, 'context-lab.html'));
});
app.on('window-all-closed', () => app.quit());
