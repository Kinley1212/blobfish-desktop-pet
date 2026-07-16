const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');

const { REQUIRED_ACTIONS, assertInside, loadCharacterPack } = require('../src/core/pack-loader');

const charactersRoot = path.join(__dirname, '..', 'src', 'packs', 'characters');

test('loads the bundled blobfish character pack', () => {
  const pack = loadCharacterPack(charactersRoot, 'blobfish');

  assert.equal(pack.manifest.id, 'blobfish');
  assert.equal(pack.manifest.size.width, 105);
  assert.match(pack.svg, /class="eye eye-left"/);
  assert.equal(pack.styles.length, pack.manifest.styles.length);
  assert.equal(pack.manifest.actions.exit, 'exit');
  assert.ok(pack.manifest.styles.includes('animations/exit.css'));
  for (const action of REQUIRED_ACTIONS) {
    assert.equal(typeof pack.manifest.actions[action], 'string');
  }
});

test('loads the grass buddy pack with compositor-friendly standard actions', () => {
  const pack = loadCharacterPack(charactersRoot, 'grass-buddy');

  assert.equal(pack.manifest.displayName, '小草团');
  assert.equal(pack.manifest.defaultLanguagePack, 'grass-buddy-zh-CN');
  assert.equal(pack.manifest.size.height, 98);
  assert.match(pack.svg, /class="grass-body-shape"/);
  assert.doesNotMatch(pack.svg, /grass-highlight/);
  assert.match(pack.svg, /class="eye eye-left"/);
  assert.equal(pack.styles.length, pack.manifest.styles.length);

  const animationCss = pack.styles.map((style) => style.css).join('\n');
  for (const action of REQUIRED_ACTIONS) {
    assert.equal(pack.manifest.actions[action], action);
  }
  assert.doesNotMatch(animationCss, /(?:^|[;{]\s*)(?:margin|top|right|bottom|left|width|height)\s*:/m);
  assert.match(animationCss, /grass-buddy-walk/);
  assert.match(animationCss, /grass-buddy-working/);
  assert.match(animationCss, /grass-buddy-exit/);

  const mouthY = Number(pack.svg.match(/class="mouth mouth-smile" d="M \d+ (\d+)/)?.[1]);
  const leftArmY = Number(pack.svg.match(/class="arm arm-left" d="M \d+ (\d+)/)?.[1]);
  assert.ok(Number.isFinite(mouthY) && Number.isFinite(leftArmY));
  assert.ok(leftArmY - mouthY >= 15, 'mouth and arms need clear vertical spacing');

  assert.match(pack.svg, /M 85 13 Q 93 14 100 18/, 'top silhouette should follow the supplied reference');
  assert.match(pack.svg, /L 150 78 L 172 75 Q 176 75 172 82 L 160 90/, 'right side tuft should follow the supplied reference');
  assert.match(pack.svg, /L 28 95 L 8 74 Q 4 72 8 72 L 31 73 L 33 46/, 'left side tuft should follow the supplied reference');
  assert.match(pack.svg, /L 42 125 Q 38 125 36 120/, 'body should keep the reference image\'s broad, nearly flat base');
  assert.match(pack.svg, /stroke-width="5\.5"/, 'body outline should retain the reference image\'s lighter line weight');
});

test('rejects invalid ids and paths outside the pack root', () => {
  assert.throws(() => loadCharacterPack(charactersRoot, '../blobfish'), /Invalid character pack id/);
  assert.throws(() => assertInside(charactersRoot, '../outside'), /escapes its root/);
});
