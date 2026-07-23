const fs = require('fs');
const path = require('path');

const PACK_ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const DIY_SHAPE_ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const DIY_SHAPE_GROUPS = ['body', 'fins'];
const ACCESSORY_SLOT_KEYS = ['face', 'hat', 'eyewear', 'hand'];
const MAX_SVG_BYTES = 512 * 1024;
const MAX_CSS_BYTES = 128 * 1024;
const MAX_SETTINGS_COPY_BYTES = 32 * 1024;
const REQUIRED_ACTIONS = ['idle', 'blink', 'roam', 'working', 'waiting', 'success', 'failed', 'hit', 'bump', 'dragging', 'exit'];
const REQUIRED_SETTINGS_COPY_KEYS = [
  'windowTitle',
  'pageTitle',
  'subtitle',
  'scheduleTitle',
  'scheduleHint',
  'quietTitle',
  'quietHint',
  'personalityTitle',
  'personalityHint',
  'motionTitle',
  'motionHint',
  'speedLabel',
  'roamWithoutTasksLabel',
  'entryHint',
  'savedStatus',
  'resetStatus',
];
const OPTIONAL_SETTINGS_COPY_KEYS = ['greetingTitle', 'greetingHint'];
const SETTINGS_COPY_KEYS = [...REQUIRED_SETTINGS_COPY_KEYS, ...OPTIONAL_SETTINGS_COPY_KEYS];

function assertInside(root, relativePath) {
  if (typeof relativePath !== 'string' || relativePath.length === 0) {
    throw new Error('Pack file path must be a non-empty string');
  }

  const resolvedRoot = path.resolve(root);
  const resolvedPath = path.resolve(resolvedRoot, relativePath);
  if (resolvedPath !== resolvedRoot && !resolvedPath.startsWith(`${resolvedRoot}${path.sep}`)) {
    throw new Error(`Pack path escapes its root: ${relativePath}`);
  }
  return resolvedPath;
}

function readTextFile(root, relativePath, maxBytes) {
  const filePath = assertInside(root, relativePath);
  const stat = fs.statSync(filePath);
  if (!stat.isFile()) {
    throw new Error(`Pack entry is not a file: ${relativePath}`);
  }
  if (stat.size > maxBytes) {
    throw new Error(`Pack file is too large: ${relativePath}`);
  }
  return fs.readFileSync(filePath, 'utf8');
}

function validateManifest(manifest, expectedId) {
  if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest)) {
    throw new Error('Character manifest must be an object');
  }
  if (!PACK_ID_PATTERN.test(expectedId) || manifest.id !== expectedId) {
    throw new Error('Character manifest id does not match its folder');
  }
  if (typeof manifest.displayName !== 'string' || manifest.displayName.trim().length === 0) {
    throw new Error('Character manifest requires displayName');
  }
  if (manifest.renderer !== 'svg') {
    throw new Error(`Unsupported character renderer: ${manifest.renderer}`);
  }
  if (!manifest.size || !Number.isFinite(manifest.size.width) || !Number.isFinite(manifest.size.height)) {
    throw new Error('Character manifest requires numeric width and height');
  }
  if (manifest.size.width < 32 || manifest.size.width > 512 || manifest.size.height < 32 || manifest.size.height > 512) {
    throw new Error('Character dimensions must be between 32 and 512 pixels');
  }
  if (typeof manifest.art !== 'string' || !manifest.art.endsWith('.svg')) {
    throw new Error('SVG character packs require an .svg art file');
  }
  if (!Array.isArray(manifest.styles) || manifest.styles.length === 0 || manifest.styles.length > 32) {
    throw new Error('Character manifest requires 1-32 style files');
  }
  for (const style of manifest.styles) {
    if (typeof style !== 'string' || !style.endsWith('.css')) {
      throw new Error('Character style entries must be .css files');
    }
  }
  if (!manifest.actions || typeof manifest.actions !== 'object') {
    throw new Error('Character manifest requires actions');
  }
  for (const action of REQUIRED_ACTIONS) {
    if (typeof manifest.actions[action] !== 'string' || manifest.actions[action].length === 0) {
      throw new Error(`Character manifest is missing action: ${action}`);
    }
  }
  if (manifest.accessories !== undefined) validateAccessorySlots(manifest.accessories);
  if (manifest.diy !== undefined) validateDiy(manifest.diy);
  if (manifest.settingsCopy !== undefined && (
    typeof manifest.settingsCopy !== 'string' || !manifest.settingsCopy.endsWith('.json')
  )) {
    throw new Error('Character settingsCopy must be a .json file');
  }
}

// Where a shared accessory hangs on this particular character, in the pack's
// own viewBox coordinates.
function validateAccessorySlots(accessories) {
  if (!accessories || typeof accessories !== 'object' || Array.isArray(accessories)) {
    throw new Error('Character accessories must be an object');
  }
  const { slots } = accessories;
  if (!slots || typeof slots !== 'object' || Array.isArray(slots)) {
    throw new Error('Character accessories.slots must be an object');
  }
  for (const key of Object.keys(slots)) {
    if (!ACCESSORY_SLOT_KEYS.includes(key)) {
      throw new Error(`Unsupported accessory slot: ${key}`);
    }
    const slot = slots[key];
    if (!slot || typeof slot !== 'object' || Array.isArray(slot)) {
      throw new Error(`accessories.slots.${key} must be an object`);
    }
    if (!Number.isFinite(slot.x) || !Number.isFinite(slot.y)) {
      throw new Error(`accessories.slots.${key} requires numeric x and y`);
    }
    if (slot.scale !== undefined && (!Number.isFinite(slot.scale) || slot.scale <= 0 || slot.scale > 8)) {
      throw new Error(`accessories.slots.${key}.scale must be between 0 and 8`);
    }
  }
}

// Shape presets end up in a `d` attribute, so the payload is restricted to
// path-command syntax and a sane length before it ever reaches the DOM.
function validatePathData(value, label) {
  if (typeof value !== 'string' || value.trim().length === 0 || value.length > 4096) {
    throw new Error(`${label} must be a non-empty path shorter than 4096 characters`);
  }
  if (!/^[-0-9.,\seEMmLlHhVvCcSsQqTtAaZz]+$/.test(value)) {
    throw new Error(`${label} contains characters that are not SVG path data`);
  }
}

function validateShapeOption(option, groupName, index) {
  const label = `diy.shapes.${groupName}[${index}]`;
  if (!option || typeof option !== 'object' || Array.isArray(option)) {
    throw new Error(`${label} must be an object`);
  }
  if (!DIY_SHAPE_ID_PATTERN.test(option.id || '')) {
    throw new Error(`${label}.id is invalid`);
  }
  if (typeof option.label !== 'string' || option.label.trim().length === 0 || option.label.length > 24) {
    throw new Error(`${label}.label must be a short string`);
  }
  if (groupName === 'fins') {
    validatePathData(option.left, `${label}.left`);
    validatePathData(option.right, `${label}.right`);
  } else {
    validatePathData(option.d, `${label}.d`);
  }
  if (option.hideShading !== undefined && typeof option.hideShading !== 'boolean') {
    throw new Error(`${label}.hideShading must be a boolean`);
  }
}

function validateDiy(diy) {
  if (!diy || typeof diy !== 'object' || Array.isArray(diy)) {
    throw new Error('Character diy must be an object');
  }
  if (typeof diy.enabled !== 'boolean') {
    throw new Error('Character diy requires a boolean enabled flag');
  }
  if (diy.shapes === undefined) return;
  if (!diy.shapes || typeof diy.shapes !== 'object' || Array.isArray(diy.shapes)) {
    throw new Error('Character diy.shapes must be an object');
  }
  for (const groupName of Object.keys(diy.shapes)) {
    if (!DIY_SHAPE_GROUPS.includes(groupName)) {
      throw new Error(`Unsupported diy shape group: ${groupName}`);
    }
    const options = diy.shapes[groupName];
    if (!Array.isArray(options) || options.length === 0 || options.length > 12) {
      throw new Error(`diy.shapes.${groupName} must list 1-12 options`);
    }
    const seen = new Set();
    options.forEach((option, index) => {
      validateShapeOption(option, groupName, index);
      if (seen.has(option.id)) throw new Error(`diy.shapes.${groupName} has a duplicate id: ${option.id}`);
      seen.add(option.id);
    });
  }
}

function validateSettingsCopy(copy) {
  if (!copy || typeof copy !== 'object' || Array.isArray(copy)) {
    throw new Error('Character settings copy must be an object');
  }
  for (const key of REQUIRED_SETTINGS_COPY_KEYS) {
    if (typeof copy[key] !== 'string' || copy[key].trim().length === 0 || copy[key].length > 240) {
      throw new Error(`Character settings copy requires a short string: ${key}`);
    }
  }
  for (const key of OPTIONAL_SETTINGS_COPY_KEYS) {
    if (copy[key] !== undefined && (
      typeof copy[key] !== 'string' || copy[key].trim().length === 0 || copy[key].length > 240
    )) {
      throw new Error(`Character settings copy requires a short string when provided: ${key}`);
    }
  }
  for (const key of Object.keys(copy)) {
    if (!SETTINGS_COPY_KEYS.includes(key)) {
      throw new Error(`Unsupported character settings copy key: ${key}`);
    }
  }
}

function loadCharacterPack(charactersRoot, id) {
  if (!PACK_ID_PATTERN.test(id)) {
    throw new Error(`Invalid character pack id: ${id}`);
  }

  const packRoot = assertInside(charactersRoot, id);
  const manifestText = readTextFile(packRoot, 'manifest.json', 64 * 1024);
  const manifest = JSON.parse(manifestText);
  validateManifest(manifest, id);

  const svg = readTextFile(packRoot, manifest.art, MAX_SVG_BYTES);
  const styles = manifest.styles.map((relativePath) => ({
    path: relativePath,
    css: readTextFile(packRoot, relativePath, MAX_CSS_BYTES),
  }));
  const settingsCopy = manifest.settingsCopy
    ? JSON.parse(readTextFile(packRoot, manifest.settingsCopy, MAX_SETTINGS_COPY_BYTES))
    : null;
  if (settingsCopy) validateSettingsCopy(settingsCopy);

  return {
    manifest,
    svg,
    styles,
    settingsCopy,
  };
}

module.exports = {
  REQUIRED_ACTIONS,
  assertInside,
  loadCharacterPack,
  validateAccessorySlots,
  validateDiy,
  validateManifest,
  validateSettingsCopy,
};
