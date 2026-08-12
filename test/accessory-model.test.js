const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');

const {
  ACCESSORY_SLOTS,
  DEFAULT_TUNING,
  accessoryTransform,
  compatibleAccessories,
  createLatestRequestGate,
  defaultAccessories,
  defaultTuning,
  getTuning,
  isDangerousSvgElementName,
  isAccessoryCompatible,
  isEmptyAccessories,
  isSafeSvgAttribute,
  normalizeAccessories,
  normalizeAccessoryMap,
  nativeExpressionForFace,
  resolveFaceId,
  supportsAccessories,
  tuningFieldsForAccessory,
  withAccessoryEquipped,
} = require('../src/core/accessory-model');
const { loadAccessory, loadAccessoryCatalog, validateAccessoryManifest } = require('../src/core/accessory-loader');
const { loadCharacterPack } = require('../src/core/pack-loader');

const accessoriesRoot = path.join(__dirname, '..', 'src', 'packs', 'accessories');
const charactersRoot = path.join(__dirname, '..', 'src', 'packs', 'characters');

test('a fresh wardrobe wears nothing and has no tuning', () => {
  const spec = defaultAccessories();

  assert.deepEqual(Object.keys(spec.equipped), ['face', 'hat', 'eyewear', 'hand', 'clock']);
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

test('a system prop can be equipped temporarily without mutating the saved spec', () => {
  const saved = normalizeAccessories({
    equipped: { hand: 'coffee' },
    tuning: { 'alarm-clock': { offsetX: 4, size: 1.2 } },
  });
  const runtime = withAccessoryEquipped(saved, 'clock', 'alarm-clock');

  assert.equal(saved.equipped.clock, null);
  assert.equal(runtime.equipped.clock, 'alarm-clock');
  assert.equal(runtime.equipped.hand, 'coffee');
  assert.equal(getTuning(runtime, 'alarm-clock').offsetX, 4);
});

test('alarm clocks keep a wider movement range without widening ordinary accessories', () => {
  const spec = normalizeAccessories({
    tuning: {
      'alarm-clock-plum-night': { width: 0.5, height: 1.8, offsetX: 999, offsetY: -999 },
      crown: { width: 0.5, height: 1.8, offsetX: 96, offsetY: -74 },
    },
  });

  assert.equal(getTuning(spec, 'alarm-clock-plum-night').offsetX, 240);
  assert.equal(getTuning(spec, 'alarm-clock-plum-night').offsetY, -180);
  assert.equal(getTuning(spec, 'alarm-clock-plum-night').width, 1);
  assert.equal(getTuning(spec, 'alarm-clock-plum-night').height, 1);
  assert.equal(getTuning(spec, 'crown').offsetX, 30);
  assert.equal(getTuning(spec, 'crown').offsetY, -30);
  assert.equal(getTuning(spec, 'crown').width, 0.5);
  assert.equal(getTuning(spec, 'crown').height, 1.8);
  assert.deepEqual(
    tuningFieldsForAccessory('alarm-clock-honey').map(({ key, min, max }) => ({ key, min, max })),
    [
      { key: 'size', min: 0.4, max: 2 },
      { key: 'offsetX', min: -240, max: 240 },
      { key: 'offsetY', min: -180, max: 180 },
    ],
  );
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

test('clock transforms use the character center as the zero point', () => {
  assert.equal(
    accessoryTransform(
      { x: 20, y: 79, scale: 0.38 },
      { x: 16, y: 27 },
      { size: 1, width: 1, height: 1, offsetX: 0, offsetY: 0 },
      { x: 70, y: 60 },
    ),
    'translate(70 60) scale(0.38 0.38) translate(-50 -50)',
  );
});

test('a late DIY art request cannot replace the newest character selection', async () => {
  const gate = createLatestRequestGate();
  const pending = new Map();
  let visibleArt = null;

  async function load(packId) {
    const request = gate.begin(packId);
    const art = await new Promise((resolve, reject) => pending.set(packId, { resolve, reject }));
    if (gate.isCurrent(request, packId)) visibleArt = art;
  }

  const first = load('blobfish');
  const second = load('grass-buddy');
  pending.get('grass-buddy').resolve('grass art');
  await second;
  pending.get('blobfish').resolve('blobfish art');
  await first;

  assert.equal(visibleArt, 'grass art');
});

test('SVG safety rules reject active content and external references without removing presentation attributes', () => {
  for (const name of ['script', 'foreignObject', 'iframe', 'object', 'embed']) {
    assert.equal(isDangerousSvgElementName(name), true, `${name} must not enter the live document`);
  }
  assert.equal(isDangerousSvgElementName('linearGradient'), false);

  assert.equal(isSafeSvgAttribute('onclick', 'run()'), false);
  assert.equal(isSafeSvgAttribute('onLoad', 'run()'), false);
  assert.equal(isSafeSvgAttribute('href', 'https://example.com/tracker.svg'), false);
  assert.equal(isSafeSvgAttribute('xlink:href', 'data:image/svg+xml,...'), false);
  assert.equal(isSafeSvgAttribute('href', '#local-gradient'), true);
  assert.equal(isSafeSvgAttribute('fill', '#cadf9a'), true);
  assert.equal(isSafeSvgAttribute('class', 'grass-fill'), true);
  assert.equal(isSafeSvgAttribute('transform', 'translate(2 4)'), true);
});

test('every bundled accessory declares a slot, an anchor and real art', () => {
  const catalog = loadAccessoryCatalog(accessoriesRoot);

  assert.equal(catalog.length, 103);
  const counts = {};
  for (const item of catalog) counts[item.slot] = (counts[item.slot] || 0) + 1;
  assert.deepEqual(counts, {
    face: 34,
    hat: 32,
    eyewear: 11,
    hand: 18,
    clock: 4,
    'message-indicator': 4,
  });
  assert.equal(new Set(catalog.map((item) => item.id)).size, catalog.length, 'ids must be unique');
  for (const item of catalog) {
    assert.match(item.svg, /^<svg viewBox="0 0 100 100"/, `${item.id} must be drawn in the shared 100x100 box`);
    assert.ok(item.anchor.x >= 0 && item.anchor.x <= 100);
    assert.ok(item.anchor.y >= 0 && item.anchor.y <= 100);
    assert.ok(item.displayName.length > 0);
    assert.equal(
      item.hidesEyes,
      item.slot === 'face' && !item.nativeExpression,
      `${item.id} should only hide eyes when it draws a replacement face`,
    );
  }
});

test('grass buddy exposes only its three native expressions', () => {
  const catalog = loadAccessoryCatalog(accessoriesRoot);
  const grass = loadCharacterPack(charactersRoot, 'grass-buddy').manifest;
  const blobfish = loadCharacterPack(charactersRoot, 'blobfish').manifest;
  const grassFaces = compatibleAccessories(catalog, grass, 'face');
  const blobfishFaces = compatibleAccessories(catalog, blobfish, 'face');

  assert.deepEqual(
    grassFaces.map((face) => face.id).sort(),
    ['face-grass-calm', 'face-grass-happy', 'face-grass-worried'],
  );
  assert.equal(blobfishFaces.length, 31);
  assert.equal(blobfishFaces.some((face) => face.id.startsWith('face-grass-')), false);
  assert.ok(isAccessoryCompatible(catalog.find((item) => item.id === 'crown'), grass));
  assert.equal(isAccessoryCompatible(catalog.find((item) => item.id === 'face-happy'), grass), false);
  assert.equal(isAccessoryCompatible(catalog.find((item) => item.id === 'face-grass-happy'), blobfish), false);
});

test('legacy and hard-coded blobfish faces map safely onto grass moods', () => {
  const catalog = loadAccessoryCatalog(accessoriesRoot);
  const grass = loadCharacterPack(charactersRoot, 'grass-buddy').manifest;
  const blobfish = loadCharacterPack(charactersRoot, 'blobfish').manifest;

  assert.equal(resolveFaceId('face-happy', grass, catalog), 'face-grass-happy');
  assert.equal(resolveFaceId('face-pitiful', grass, catalog), 'face-grass-worried');
  assert.equal(resolveFaceId('face-determined', grass, catalog), 'face-grass-calm');
  assert.equal(resolveFaceId('face-does-not-exist', grass, catalog), null);
  assert.equal(resolveFaceId('face-grass-happy', blobfish, catalog), null);
  assert.equal(nativeExpressionForFace('face-pitiful', grass, catalog), 'worried');
  assert.equal(nativeExpressionForFace(null, grass, catalog), 'calm');
});

test('accessory manifests are checked before their art is read', () => {
  const valid = { id: 'crown', displayName: '小皇冠', slot: 'hat', art: 'art/accessory.svg', anchor: { x: 50, y: 70 } };

  assert.doesNotThrow(() => validateAccessoryManifest(valid, 'crown'));
  assert.throws(() => validateAccessoryManifest(valid, 'bow'), /does not match its folder/);
  assert.throws(() => validateAccessoryManifest({ ...valid, slot: 'tail' }, 'crown'), /Unsupported accessory slot/);
  assert.throws(() => validateAccessoryManifest({ ...valid, art: 'art/evil.js' }, 'crown'), /\.svg art file/);
  assert.throws(() => validateAccessoryManifest({ ...valid, anchor: { x: 150, y: 4 } }, 'crown'), /inside the 100x100/);
  assert.throws(
    () => validateAccessoryManifest({ ...valid, slot: 'face', nativeExpression: 'happy' }, 'crown'),
    /Native expressions require/,
  );
  assert.throws(() => loadAccessory(accessoriesRoot, '../characters'), /Invalid accessory id/);
});

test('bundled customisable characters offer every accessory slot', () => {
  for (const id of ['blobfish', 'blobfish-wotou', 'grass-buddy']) {
    const { manifest } = loadCharacterPack(charactersRoot, id);
    assert.ok(supportsAccessories(manifest), `${id} should support accessories`);
    for (const slot of ACCESSORY_SLOTS) {
      const anchor = manifest.accessories.slots[slot.key];
      assert.ok(Number.isFinite(anchor.x) && Number.isFinite(anchor.y), `${id} needs a ${slot.key} anchor`);
    }
  }

});
