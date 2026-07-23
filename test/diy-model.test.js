const assert = require('node:assert/strict');
const test = require('node:test');

const {
  DEFAULT_DIY,
  defaultDiy,
  isDefaultDiy,
  layerTransform,
  normalizeDiy,
  normalizeDiyMap,
  supportsDiy,
  transformAttribute,
} = require('../src/core/diy-model');

test('a fresh spec leaves every part at its original size and place', () => {
  const spec = defaultDiy();

  assert.deepEqual(spec.body, { width: 1, height: 1, shape: 'default' });
  assert.deepEqual(spec.fins, { size: 1, offsetX: 0, offsetY: 0, shape: 'default' });
  assert.deepEqual(spec.eyes, { size: 1, spacing: 0, offsetY: 0 });
  assert.deepEqual(spec.mouth, { size: 1, offsetY: 0 });
  assert.deepEqual(spec.nose, { size: 1, offsetY: 0 });
  assert.ok(isDefaultDiy(spec));
  assert.ok(isDefaultDiy(undefined));
});

test('out-of-range and unreadable values are clamped instead of rejected', () => {
  const spec = normalizeDiy({
    body: { width: 99, height: -4 },
    fins: { size: 'wide', offsetX: 40, offsetY: -40 },
    eyes: { size: 1.25, spacing: 3.3, offsetY: null },
    nose: { size: 1.2 },
  });

  assert.equal(spec.body.width, 1.3);
  assert.equal(spec.body.height, 0.7);
  assert.equal(spec.fins.size, 1, 'a non-numeric slider keeps its default');
  assert.equal(spec.fins.offsetX, 16);
  assert.equal(spec.fins.offsetY, -16);
  assert.equal(spec.eyes.size, 1.25);
  assert.equal(spec.eyes.spacing, 3.5, 'values snap to the slider step');
  assert.equal(spec.eyes.offsetY, 0);
  assert.equal(spec.nose.size, 1.2);
});

test('shape ids survive only when they look like pack ids', () => {
  assert.equal(normalizeDiy({ body: { shape: 'wotou' } }).body.shape, 'wotou');
  assert.equal(normalizeDiy({ fins: { shape: 'long-fin' } }).fins.shape, 'long-fin');
  assert.equal(normalizeDiy({ body: { shape: '../../etc/passwd' } }).body.shape, 'default');
  assert.equal(normalizeDiy({ fins: { shape: 42 } }).fins.shape, 'default');
});

test('a garbage spec falls back to the defaults rather than throwing', () => {
  assert.deepEqual(normalizeDiy(null), DEFAULT_DIY);
  assert.deepEqual(normalizeDiy('nope'), DEFAULT_DIY);
  assert.deepEqual(normalizeDiy([1, 2]), DEFAULT_DIY);
  assert.deepEqual(normalizeDiy({ body: 'nope' }), DEFAULT_DIY);
});

test('the per-character map drops untouched packs and invalid keys', () => {
  const map = normalizeDiyMap({
    blobfish: { nose: { size: 1.2 } },
    'blobfish-wotou': defaultDiy(),
    'Bad Id': { nose: { size: 1.2 } },
  });

  assert.deepEqual(Object.keys(map), ['blobfish']);
  assert.equal(map.blobfish.nose.size, 1.2);
  assert.deepEqual(normalizeDiyMap(undefined), {});
});

test('paired parts read one slider with mirrored horizontal signs', () => {
  const spec = normalizeDiy({
    fins: { size: 1.2, offsetX: 4, offsetY: -2 },
    eyes: { size: 0.9, spacing: 3, offsetY: 1.5 },
  });

  assert.deepEqual(layerTransform('finLeft', spec), { scaleX: 1.2, scaleY: 1.2, dx: -4, dy: -2 });
  assert.deepEqual(layerTransform('finRight', spec), { scaleX: 1.2, scaleY: 1.2, dx: 4, dy: -2 });
  assert.deepEqual(layerTransform('eyeLeft', spec), { scaleX: 0.9, scaleY: 0.9, dx: -3, dy: 1.5 });
  assert.deepEqual(layerTransform('eyeRight', spec), { scaleX: 0.9, scaleY: 0.9, dx: 3, dy: 1.5 });
});

test('the body stretches on two independent axes', () => {
  const spec = normalizeDiy({ body: { width: 1.1, height: 0.9 } });

  assert.deepEqual(layerTransform('body', spec), { scaleX: 1.1, scaleY: 0.9, dx: 0, dy: 0 });
});

test('an untouched part produces no transform at all', () => {
  const identity = layerTransform('mouth', defaultDiy());

  assert.equal(transformAttribute(identity, { x: 70, y: 90 }), '');
});

test('a transform scales around the part own centre', () => {
  const transform = layerTransform('nose', normalizeDiy({ nose: { size: 1.2, offsetY: 3 } }));

  assert.equal(transformAttribute(transform, { x: 70, y: 80 }), 'translate(70 83) scale(1.2 1.2) translate(-70 -80)');
});

test('only packs that opt in are customisable', () => {
  assert.ok(supportsDiy({ diy: { enabled: true } }));
  assert.equal(supportsDiy({ diy: { enabled: false } }), false);
  assert.equal(supportsDiy({}), false);
  assert.equal(supportsDiy(null), false);
});
