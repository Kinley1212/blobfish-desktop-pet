const fs = require('fs');
const path = require('path');
const { validateDialogue } = require('./dialogue-model');

const PACK_ID_PATTERN = /^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$/;
const MAX_BYTES = 128 * 1024;

// Dialogue packs are named after the language pack they speak for, so the
// conversation matches whatever voice the pet is currently using.
function loadDialoguePack(dialoguesRoot, languagePackId) {
  if (!PACK_ID_PATTERN.test(languagePackId)) {
    throw new Error(`Invalid dialogue pack id: ${languagePackId}`);
  }
  const filePath = path.join(dialoguesRoot, `${languagePackId}.json`);
  const resolved = path.resolve(filePath);
  if (resolved !== path.resolve(dialoguesRoot, `${languagePackId}.json`)) {
    throw new Error('Dialogue path escaped its root');
  }
  const stat = fs.statSync(filePath);
  if (!stat.isFile() || stat.size > MAX_BYTES) {
    throw new Error(`Dialogue pack is missing or too large: ${languagePackId}`);
  }
  const pack = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  return validateDialogue(pack);
}

// A missing or broken pack just means "no chat available" rather than a crash.
function loadDialoguePackSafe(dialoguesRoot, languagePackId) {
  try {
    return loadDialoguePack(dialoguesRoot, languagePackId);
  } catch (error) {
    if (error.code !== 'ENOENT') {
      console.error(`Ignoring invalid dialogue pack ${languagePackId}: ${error.message}`);
    }
    return null;
  }
}

module.exports = { loadDialoguePack, loadDialoguePackSafe };
