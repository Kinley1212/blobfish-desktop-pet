const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');

const {
  ACCESSORY_SLOTS,
  accessoryTransform,
  defaultAccessories,
  isEmptyAccessories,
  normalizeAccessories,
  normalizeAccessoryMap,
  supportsAccessories,
} = require('../src/core/accessory-model');
const { loadAccessory, loadAccessoryCatalog, validateAccessoryManifest } = require('../src/core/accessory-loader');

const accessoriesRoot = path.join(__dirname, '..', 'src', 'packs', 'accessories');
const charactersRoot = path.join(__dirname, '..', 'src', 'packs', 'characters');
const { loadCharacterPack } = require('../src/core/pack-loader');

test('a fresh wardrobe has every slot empty', () => {
  const spec = defaultAccessories();

  assert.deepEqual(Object.keys(spec), ['face', 'hat', 'eyewear', 'hand']);
  for (const slot of ACCESSORY_SLOTS) {
    assert.deepEqual(spec[slot.key], { id: null, width: 1, height: 1, offsetX: 0, offsetY: 0 });
  }
  assert.ok(isEmptyAccessories(spec));
});

test('equipped ids and nudges normalise, garbage does not survive', () => {
  const spec = normalizeAccessories({
    hat: { id: 'straw-hat', width: 9, offsetX: -3.3 },
    eyewear: { id: '../secret', offsetY: 4 },
    hand: { id: 42 },
  });

  assert.equal(spec.hat.id, 'straw-hat');
  assert.equal(spec.hat.width, 2, 'width is clamped to the slider maximum');
  assert.equal(spec.hat.offsetX, -3.5, 'offsets snap to the slider step');
  assert.equal(spec.eyewear.id, null, 'a path-like id is rejected');
  assert.equal(spec.eyewear.offsetY, 4, 'a rejected id still keeps valid nudges');
  assert.equal(spec.hand.id, null);
  assert.deepEqual(normalizeAccessories(null), defaultAccessories());
});

test('a config from the uniform-size era loads with both axes seeded', () => {
  const spec = normalizeAccessories({ hat: { id: 'crown', size: 1.4 }, hand: { id: 'coffee', size: 0.8, height: 1.5 } });

  assert.equal(spec.hat.width, 1.4);
  assert.equal(spec.hat.height, 1.4);
  assert.equal(spec.hand.width, 0.8, 'the legacy value still seeds the axis it is missing');
  assert.equal(spec.hand.height, 1.5, 'an explicit axis wins over the legacy value');
});

test('a spec with nothing equipped counts as empty however it was nudged', () => {
  assert.ok(isEmptyAccessories({ hat: { id: null, width: 1.6, offsetX: 12 } }));
  assert.equal(isEmptyAccessories({ hat: { id: 'crown' } }), false);
});

test('the per-character map keeps only characters that wear something', () => {
  const map = normalizeAccessoryMap({
    blobfish: { hat: { id: 'crown' } },
    'blobfish-wotou': { hand: { id: null, width: 1.4 } },
    'Bad Id': { hat: { id: 'crown' } },
  });

  assert.deepEqual(Object.keys(map), ['blobfish']);
  assert.equal(map.blobfish.hat.id, 'crown');
});

test('an accessory lands on the slot with the character scale and the user nudges combined', () => {
  const transform = accessoryTransform(
    { x: 70, y: 20, scale: 1.15 },
    { x: 50, y: 76 },
    { width: 1.2, height: 0.8, offsetX: -4, offsetY: 2 },
  );

  assert.equal(transform, 'translate(66 22) scale(1.38 0.92) translate(-50 -76)');
});

test('every bundled accessory declares a slot, an anchor and real art', () => {
  const catalog = loadAccessoryCatalog(accessoriesRoot);

  assert.equal(catalog.length, 33);
  const counts = {};
  for (const item of catalog) counts[item.slot] = (counts[item.slot] || 0) + 1;
  assert.deepEqual(counts, { face: 8, hat: 9, eyewear: 7, hand: 9 });
  for (const item of catalog) {
    assert.equal(item.hidesEyes, item.slot === 'face', `${item.id} should only hide the eyes when it is an expression`);
  }
  assert.equal(new Set(catalog.map((item) => item.id)).size, catalog.length, 'ids must be unique');
  for (const item of catalog) {
    assert.match(item.svg, /^<svg viewBox="0 0 100 100"/, `${item.id} must be drawn in the shared 100x100 box`);
    assert.ok(item.anchor.x >= 0 && item.anchor.x <= 100);
    assert.ok(item.anchor.y >= 0 && item.anchor.y <= 100);
    assert.ok(item.displayName.length > 0);
  }
});

test('accessory manifests are checked before their art is read', () => {
  const valid = { id: 'crown', displayName: '小皇冠', slot: 'hat', art: 'art/accessory.svg', anchor: { x: 50, y: 70 } };

  assert.doesNotThrow(() => validateAccessoryManifest(valid, 'crown'));
  assert.throws(() => validateAccessoryManifest(valid, 'bow'), /does not match its folder/);
  assert.throws(() => validateAccessoryManifest({ ...valid, slot: 'tail' }, 'crown'), /Unsupported accessory slot/);
  assert.throws(() => validateAccessoryManifest({ ...valid, art: 'art/evil.js' }, 'crown'), /\.svg art file/);
  assert.throws(() => validateAccessoryManifest({ ...valid, anchor: { x: 150, y: 4 } }, 'crown'), /inside the 100x100/);
  assert.throws(() => loadAccessory(accessoriesRoot, '../characters'), /Invalid accessory id/);
});

test('both blobfish packs offer every slot and the grass buddy offers none', () => {
  for (const id of ['blobfish', 'blobfish-wotou']) {
    const { manifest } = loadCharacterPack(charactersRoot, id);
    assert.ok(supportsAccessories(manifest), `${id} should support accessories`);
    for (const slot of ACCESSORY_SLOTS) {
      const anchor = manifest.accessories.slots[slot.key];
      assert.ok(Number.isFinite(anchor.x) && Number.isFinite(anchor.y), `${id} needs a ${slot.key} anchor`);
    }
  }

  assert.equal(supportsAccessories(loadCharacterPack(charactersRoot, 'grass-buddy').manifest), false);
});
