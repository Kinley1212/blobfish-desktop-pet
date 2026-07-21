const path = require('path');

// Single source of truth for the task-completion sound options, shared by the
// main process (to resolve which file to play), the config validator (to
// reject unknown ids), and the settings UI (to render the dropdown). Every id
// maps to a built-in macOS system sound in /System/Library/Sounds, so nothing
// needs to be bundled.
const SYSTEM_SOUNDS_DIR = '/System/Library/Sounds';

const TASK_COMPLETE_SOUNDS = Object.freeze([
  Object.freeze({ id: 'Glass', label: '玻璃叮（清脆）' }),
  Object.freeze({ id: 'Ping', label: 'Ping（清亮）' }),
  Object.freeze({ id: 'Hero', label: 'Hero（英雄感）' }),
  Object.freeze({ id: 'Submarine', label: '潜水艇（低沉）' }),
  Object.freeze({ id: 'Tink', label: 'Tink（轻响）' }),
  Object.freeze({ id: 'Pop', label: 'Pop（气泡）' }),
  Object.freeze({ id: 'Purr', label: 'Purr（呼噜）' }),
  Object.freeze({ id: 'Bottle', label: 'Bottle（瓶盖）' }),
  Object.freeze({ id: 'Funk', label: 'Funk（放克）' }),
]);

const DEFAULT_TASK_COMPLETE_SOUND_ID = 'Glass';

function isValidTaskCompleteSoundId(id) {
  return TASK_COMPLETE_SOUNDS.some((sound) => sound.id === id);
}

// Returns the absolute path to the sound file for an id, or null if the id
// isn't in the catalog (caller decides how to fall back).
function taskCompleteSoundPath(id) {
  if (!isValidTaskCompleteSoundId(id)) return null;
  return path.join(SYSTEM_SOUNDS_DIR, `${id}.aiff`);
}

module.exports = {
  SYSTEM_SOUNDS_DIR,
  TASK_COMPLETE_SOUNDS,
  DEFAULT_TASK_COMPLETE_SOUND_ID,
  isValidTaskCompleteSoundId,
  taskCompleteSoundPath,
};
