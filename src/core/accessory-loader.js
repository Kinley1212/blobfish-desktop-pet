const fs = require('fs');
const path = require('path');
const { ACCESSORY_SLOTS } = require('./accessory-model');
const { assertInside } = require('./pack-loader');

const ACCESSORY_ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const MAX_ART_BYTES = 64 * 1024;

function validateAccessoryManifest(manifest, expectedId) {
  if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest)) {
    throw new Error('Accessory manifest must be an object');
  }
  if (!ACCESSORY_ID_PATTERN.test(expectedId) || manifest.id !== expectedId) {
    throw new Error('Accessory manifest id does not match its folder');
  }
  if (typeof manifest.displayName !== 'string' || manifest.displayName.trim().length === 0 || manifest.displayName.length > 24) {
    throw new Error('Accessory manifest requires a short displayName');
  }
  if (!ACCESSORY_SLOTS.some((slot) => slot.key === manifest.slot)) {
    throw new Error(`Unsupported accessory slot: ${manifest.slot}`);
  }
  if (typeof manifest.art !== 'string' || !manifest.art.endsWith('.svg')) {
    throw new Error('Accessory manifest requires an .svg art file');
  }
  // The anchor is the point in the art's own 100x100 box that lands on the
  // character's slot, so it has to sit inside that box.
  if (!manifest.anchor || !Number.isFinite(manifest.anchor.x) || !Number.isFinite(manifest.anchor.y)) {
    throw new Error('Accessory manifest requires a numeric anchor');
  }
  if (manifest.anchor.x < 0 || manifest.anchor.x > 100 || manifest.anchor.y < 0 || manifest.anchor.y > 100) {
    throw new Error('Accessory anchor must sit inside the 100x100 art box');
  }
  if (manifest.hidesEyes !== undefined && typeof manifest.hidesEyes !== 'boolean') {
    throw new Error('Accessory hidesEyes must be a boolean');
  }
}

function loadAccessory(accessoriesRoot, id) {
  if (!ACCESSORY_ID_PATTERN.test(id)) {
    throw new Error(`Invalid accessory id: ${id}`);
  }

  const root = assertInside(accessoriesRoot, id);
  const manifest = JSON.parse(fs.readFileSync(assertInside(root, 'manifest.json'), 'utf8'));
  validateAccessoryManifest(manifest, id);

  const artPath = assertInside(root, manifest.art);
  const stat = fs.statSync(artPath);
  if (!stat.isFile() || stat.size > MAX_ART_BYTES) {
    throw new Error(`Accessory art is missing or too large: ${manifest.art}`);
  }

  return {
    id: manifest.id,
    displayName: manifest.displayName,
    slot: manifest.slot,
    anchor: { x: manifest.anchor.x, y: manifest.anchor.y },
    hidesEyes: manifest.hidesEyes === true,
    svg: fs.readFileSync(artPath, 'utf8'),
  };
}

// One bad accessory shouldn't hide the rest of the wardrobe.
function loadAccessoryCatalog(accessoriesRoot) {
  if (!fs.existsSync(accessoriesRoot)) return [];
  return fs.readdirSync(accessoriesRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      try {
        return loadAccessory(accessoriesRoot, entry.name);
      } catch (error) {
        console.error(`Ignoring invalid accessory ${entry.name}: ${error.message}`);
        return null;
      }
    })
    .filter(Boolean)
    // Sorted by name so each slot's dropdown reads in a stable, human order.
    .sort((a, b) => a.displayName.localeCompare(b.displayName, 'zh-Hans'));
}

module.exports = {
  loadAccessory,
  loadAccessoryCatalog,
  validateAccessoryManifest,
};
