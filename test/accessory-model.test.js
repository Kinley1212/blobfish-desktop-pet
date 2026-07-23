const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');

const {
  ACCESSORY_SLOTS,
  DEFAULT_TUNING,
  accessoryTransform,
  defaultAccessories,
  defaultTuning,
  getTuning,
  isEmptyAccessories,
  normalizeAccessories,
  normalizeAccessoryMap,
  supportsAccessories,
} = require('../src/core/accessory-model');
const { loadAccessory, loadAccessoryCatalog, validateAccessoryManifest } = require('../src/core/accessory-loader');
const { loadCharacterPack } = require('../src/core/pack-loader');

const accessoriesRoot = path.join(__dirname, '..', 'src', 'packs', 'accessories');
const charactersRoot = path.join(__dirname, '..', 'src', 'packs', 'characters');

test('a fresh wardrobe wears nothing and has no tuning', () => {
  const spec = defaultAccessories();

  assert.deepEqual(Object.keys(spec.equipped), ['face', 'hat', 'eyewear', 'hand']);
  for (const slot of ACCESSORY_SLOTS) assert.equal(spec.equipped[slot.key], null);
  assert.deepEqual(spec.tuning, {});
  assert.deepEqual(defaultTuning(), { size: 1, width: 1, height: 1, offsetX: 0, offsetY: 0 });
  assert.ok(isEmptyAccessories(spec));
});

test('each accessory keeps its own fit, so swapping never loses the other one', () => {
  const spec = normalizeAccessories({
    equipped: { hat: 'straw-hat' },
    tuning: {
      'straw-hat': { size: 1.2, offsetY: -3 },
      beanie: { size: 0.8, width: 1.4 },
    },
  });

  assert.equal(spec.equipped.hat, 'straw-hat');
  assert.equal(getTuning(spec, 'straw-hat').size, 1.2);
  assert.equal(getTuning(spec, 'straw-hat').offsetY, -3);
  assert.equal(getTuning(spec, 'beanie').size, 0.8, 'the hat that is not worn keeps its numbers');
  assert.equal(getTuning(spec, 'beanie').width, 1.4);
  assert.deepEqual(getTuning(spec, 'crown'), DEFAULT_TUNING, 'an untouched piece starts at the defaults');
});

test('out-of-range and unreadable values are clamped instead of rejected', () => {
  const spec = normalizeAccessories({
    equipped: { hat: 'straw-hat', eyewear: '../secret', hand: 42 },
    tuning: { 'straw-hat': { size: 9, width: 'wide', offsetX: -3.3 }, 'Bad Id': { size: 1.5 } },
  });

  assert.equal(spec.equipped.hat, 'straw-hat');
  assert.equal(spec.equipped.eyewear, null, 'a path-like id is rejected');
  assert.equal(spec.equipped.hand, null);
  assert.equal(getTuning(spec, 'straw-hat').size, 2, 'size is clamped to the slider maximum');
  assert.equal(getTuning(spec, 'straw-hat').width, 1, 'a non-numeric slider keeps its default');
  assert.equal(getTuning(spec, 'straw-hat').offsetX, -3.5, 'offsets snap to the slider step');
  assert.equal(Object.keys(spec.tuning).includes('Bad Id'), false);
  assert.deepEqual(normalizeAccessories(null), defaultAccessories());
});

test('a config from the slot-shaped era folds its numbers onto the worn piece', () => {
  const spec = normalizeAccessories({
    face: { id: 'face-dizzy', size: 1.3 },
    hat: { id: 'crown', size: 1.4, offsetY: 2 },
    hand: { id: null, size: 1.9 },
  });

  assert.equal(spec.equipped.face, 'face-dizzy');
  assert.equal(spec.equipped.hat, 'crown');
  assert.equal(getTuning(spec, 'crown').size, 1.4);
  assert.equal(getTuning(spec, 'crown').offsetY, 2);
  assert.deepEqual(spec.tuning['face-dizzy'], undefined, 'an expression carries no tuning');
  assert.equal(Object.keys(spec.tuning).length, 1, 'an empty slot leaves nothing behind');
});

test('a spec counts as empty only when nothing is worn and nothing was tuned', () => {
  assert.ok(isEmptyAccessories({ equipped: {}, tuning: {} }));
  assert.equal(isEmptyAccessories({ equipped: { hat: 'crown' }, tuning: {} }), false);
  assert.equal(isEmptyAccessories({ equipped: {}, tuning: { crown: { size: 1.5 } } }), false);
});

test('the per-character map keeps only characters with something saved', () => {
  const map = normalizeAccessoryMap({
    blobfish: { equipped: { hat: 'crown' }, tuning: {} },
    'blobfish-wotou': { equipped: {}, tuning: { crown: defaultTuning() } },
    'Bad Id': { equipped: { hat: 'crown' }, tuning: {} },
  });

  assert.deepEqual(Object.keys(map), ['blobfish']);
  assert.equal(map.blobfish.equipped.hat, 'crown');
});

test('size scales both axes and width and height stretch on top of it', () => {
  const anchor = { x: 70, y: 20, scale: 1.15 };
  const art = { x: 50, y: 76 };

  assert.equal(
    accessoryTransform(anchor, art, { size: 1, width: 1, height: 1, offsetX: 0, offsetY: 0 }),
    'translate(70 20) scale(1.15 1.15) translate(-50 -76)',
  );
  assert.equal(
    accessoryTransform(anchor, art, { size: 1.2, width: 1, height: 1, offsetX: 0, offsetY: 0 }),
    'translate(70 20) scale(1.38 1.38) translate(-50 -76)',
    'size alone stays proportional',
  );
  assert.equal(
    accessoryTransform(anchor, art, { size: 1.2, width: 1, height: 0.5, offsetX: -4, offsetY: 2 }),
    'translate(66 22) scale(1.38 0.69) translate(-50 -76)',
  );
});

test('every bundled accessory declares a slot, an anchor and real art', () => {
  const catalog = loadAccessoryCatalog(accessoriesRoot);

  assert.equal(catalog.length, 33);
  const counts = {};
  for (const item of catalog) counts[item.slot] = (counts[item.slot] || 0) + 1;
  assert.deepEqual(counts, { face: 8, hat: 9, eyewear: 7, hand: 9 });
  assert.equal(new Set(catalog.map((item) => item.id)).size, catalog.length, 'ids must be unique');
  for (const item of catalog) {
    assert.match(item.svg, /^<svg viewBox="0 0 100 100"/, `${item.id} must be drawn in the shared 100x100 box`);
    assert.ok(item.anchor.x >= 0 && item.anchor.x <= 100);
    assert.ok(item.anchor.y >= 0 && item.anchor.y <= 100);
    assert.ok(item.displayName.length > 0);
    assert.equal(item.hidesEyes, item.slot === 'face', `${item.id} should only hide the eyes when it is an expression`);
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
