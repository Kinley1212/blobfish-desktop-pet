const { execFile } = require('child_process');

function playTaskSoundFile(soundPath, options = {}) {
  if (!soundPath) return false;
  const platform = options.platform || process.platform;
  const execFileImpl = options.execFile || execFile;
  const beep = options.beep || (() => {});
  const onError = options.onError || (() => {});

  if (platform === 'darwin') {
    execFileImpl('/usr/bin/afplay', [soundPath], (error) => {
      if (!error) return;
      onError(error);
      beep();
    });
    return true;
  }

  beep();
  return true;
}

module.exports = {
  playTaskSoundFile,
};
