const fs = require('fs');
const path = require('path');
const { assertInside } = require('./pack-loader');

const PACK_ID_PATTERN = /^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$/;
const PHRASE_ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const EVENT_PATTERN = /^[a-z][A-Za-z0-9]*(?:\.[a-z][A-Za-z0-9]*)+$/;
const PLACEHOLDER_PATTERN = /\{([A-Za-z][A-Za-z0-9]*)\}/g;
const MAX_JSON_BYTES = 256 * 1024;
const MAX_PHRASE_LENGTH = 240;
const ALLOWED_RARITIES = new Set(['common', 'uncommon', 'rare']);

function readJson(root, relativePath) {
  const filePath = assertInside(root, relativePath);
  const stat = fs.statSync(filePath);
  if (!stat.isFile()) throw new Error(`Language pack entry is not a file: ${relativePath}`);
  if (stat.size > MAX_JSON_BYTES) throw new Error(`Language pack file is too large: ${relativePath}`);

  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    throw new Error(`Invalid JSON in language pack file ${relativePath}: ${error.message}`);
  }
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function validateConditions(conditions, phraseId) {
  if (conditions === undefined) return;
  if (!isPlainObject(conditions)) throw new Error(`Phrase ${phraseId} conditions must be an object`);

  for (const [key, value] of Object.entries(conditions)) {
    const validScalar = typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean';
    const validArray = Array.isArray(value) && value.length <= 32 && value.every((entry) => (
      typeof entry === 'string' || typeof entry === 'number'
    ));
    if (!validScalar && !validArray) {
      throw new Error(`Phrase ${phraseId} has an invalid condition: ${key}`);
    }
  }
}

function validatePhrase(phrase, sourcePath) {
  if (!isPlainObject(phrase)) throw new Error(`Phrase in ${sourcePath} must be an object`);
  if (!PHRASE_ID_PATTERN.test(phrase.id || '')) throw new Error(`Invalid phrase id in ${sourcePath}`);
  if (!EVENT_PATTERN.test(phrase.event || '')) throw new Error(`Phrase ${phrase.id} has an invalid event`);
  if (typeof phrase.text !== 'string' || phrase.text.length === 0 || phrase.text.length > MAX_PHRASE_LENGTH) {
    throw new Error(`Phrase ${phrase.id} text must contain 1-${MAX_PHRASE_LENGTH} characters`);
  }
  if (phrase.weight !== undefined && (!Number.isFinite(phrase.weight) || phrase.weight <= 0 || phrase.weight > 100)) {
    throw new Error(`Phrase ${phrase.id} has an invalid weight`);
  }
  if (phrase.cooldownMs !== undefined && (
    !Number.isInteger(phrase.cooldownMs) || phrase.cooldownMs < 0 || phrase.cooldownMs > 7 * 24 * 60 * 60 * 1000
  )) {
    throw new Error(`Phrase ${phrase.id} has an invalid cooldownMs`);
  }
  if (phrase.rarity !== undefined && !ALLOWED_RARITIES.has(phrase.rarity)) {
    throw new Error(`Phrase ${phrase.id} has an invalid rarity`);
  }
  validateConditions(phrase.conditions, phrase.id);

  return [...phrase.text.matchAll(PLACEHOLDER_PATTERN)].map((match) => match[1]);
}

function validateManifest(manifest, expectedId) {
  if (!isPlainObject(manifest)) throw new Error('Language manifest must be an object');
  if (!PACK_ID_PATTERN.test(expectedId) || manifest.id !== expectedId) {
    throw new Error('Language manifest id does not match its folder');
  }
  if (typeof manifest.displayName !== 'string' || manifest.displayName.trim().length === 0) {
    throw new Error('Language manifest requires displayName');
  }
  if (typeof manifest.locale !== 'string' || manifest.locale.trim().length === 0) {
    throw new Error('Language manifest requires locale');
  }
  if (!Number.isInteger(manifest.version) || manifest.version < 1) {
    throw new Error('Language manifest requires a positive integer version');
  }
  if (typeof manifest.style !== 'string' || !manifest.style.endsWith('.json')) {
    throw new Error('Language manifest requires a JSON style file');
  }
  if (!isPlainObject(manifest.files)) throw new Error('Language manifest requires files');
  for (const group of ['original', 'additions']) {
    if (!Array.isArray(manifest.files[group]) || manifest.files[group].length === 0) {
      throw new Error(`Language manifest requires a non-empty ${group} file list`);
    }
    if (manifest.files[group].length > 64 || manifest.files[group].some((entry) => (
      typeof entry !== 'string' || !entry.endsWith('.json')
    ))) {
      throw new Error(`Language manifest has an invalid ${group} file list`);
    }
  }
}

function loadLanguagePack(languagesRoot, id) {
  if (!PACK_ID_PATTERN.test(id)) throw new Error(`Invalid language pack id: ${id}`);

  const packRoot = assertInside(languagesRoot, id);
  const manifest = readJson(packRoot, 'manifest.json');
  validateManifest(manifest, id);
  const style = readJson(packRoot, manifest.style);
  if (!isPlainObject(style)) throw new Error('Language style must be an object');

  const seenIds = new Set();
  const phrases = [];
  for (const group of ['original', 'additions']) {
    for (const sourcePath of manifest.files[group]) {
      const source = readJson(packRoot, sourcePath);
      if (!isPlainObject(source) || typeof source.category !== 'string' || !Array.isArray(source.phrases)) {
        throw new Error(`Language phrase file has an invalid shape: ${sourcePath}`);
      }

      for (const phrase of source.phrases) {
        const placeholders = validatePhrase(phrase, sourcePath);
        if (seenIds.has(phrase.id)) throw new Error(`Duplicate phrase id: ${phrase.id}`);
        seenIds.add(phrase.id);
        phrases.push(Object.freeze({
          ...phrase,
          conditions: phrase.conditions ? Object.freeze({ ...phrase.conditions }) : undefined,
          placeholders: Object.freeze(placeholders),
          sourceGroup: group,
          category: source.category,
          sourcePath,
        }));
      }
    }
  }

  return Object.freeze({
    manifest: Object.freeze({ ...manifest }),
    style: Object.freeze({ ...style }),
    phrases: Object.freeze(phrases),
  });
}

module.exports = {
  loadLanguagePack,
  validateManifest,
  validatePhrase,
};
