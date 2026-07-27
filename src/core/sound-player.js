function playTaskSoundFile(soundPath, options = {}) {
  const {
    execFile: execFileImpl,
    beep = () => {},
    platform = process.platform,
    onError = () => {},
  } = options;

  if (!soundPath) return false;
  if (platform === 'darwin') {
    if (typeof execFileImpl !== 'function') return false;
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
