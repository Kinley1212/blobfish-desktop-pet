const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');

const {
  REQUIRED_ACTIONS,
  assertInside,
  loadCharacterPack,
  validateDiy,
  validateEmbeddedImages,
  validateManifest,
  validateSettingsCopy,
} = require('../src/core/pack-loader');

const charactersRoot = path.join(__dirname, '..', 'src', 'packs', 'characters');

test('loads the bundled blobfish character pack', () => {
  const pack = loadCharacterPack(charactersRoot, 'blobfish');

  assert.equal(pack.manifest.id, 'blobfish');
  assert.equal(pack.manifest.size.width, 105);
  assert.match(pack.svg, /class="eye eye-left"/);
  assert.equal(pack.styles.length, pack.manifest.styles.length);
  assert.equal(pack.manifest.actions.exit, 'exit');
  assert.ok(pack.manifest.styles.includes('animations/exit.css'));
  assert.equal(pack.settingsCopy.pageTitle, '水滴鱼');
  assert.equal(pack.settingsCopy.windowTitle, '水滴鱼设置');
  assert.equal(pack.settingsCopy.greetingTitle, '每天第一次见面');
  const animationCss = pack.styles.map((style) => style.css).join('\n');
  assert.match(animationCss, /@keyframes blobfish-swim[\s\S]*translate: 0 -5px/);
  assert.doesNotMatch(
    animationCss,
    /@keyframes blobfish-swim[\s\S]*margin-bottom/,
    'top-positioned pets need a real vertical translation instead of the legacy bottom margin',
  );
  for (const motion of ['idle', 'roam', 'working']) {
    assert.match(
      animationCss,
      new RegExp(`#pet\\[data-motion="${motion}"\\][\\s\\S]*?animation: blobfish-swim 0\\.9s`),
      `${motion} should preserve the original 1.0 swim bob`,
    );
  }
  assert.match(animationCss, /blobfish-swim 0\.9s infinite ease-in-out,[\s\S]*blobfish-waiting-sway/);
  for (const action of REQUIRED_ACTIONS) {
    assert.equal(typeof pack.manifest.actions[action], 'string');
  }
});

test('loads the grass buddy pack with compositor-friendly standard actions', () => {
  const pack = loadCharacterPack(charactersRoot, 'grass-buddy');

  assert.equal(pack.manifest.displayName, '小草团');
  assert.equal(pack.manifest.defaultLanguagePack, 'grass-buddy-zh-CN');
  assert.equal(pack.manifest.size.height, 98);
  assert.equal(pack.settingsCopy.pageTitle, '小草团');
  assert.equal(pack.settingsCopy.speedLabel, '走路速度');
  assert.equal(pack.settingsCopy.greetingTitle, '醒来长一句');
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

  assert.match(pack.svg, /class="grass-outline"/, 'body should preserve the reference image\'s irregular outer line weight');
  assert.match(pack.svg, /class="grass-fill"/, 'body should preserve the reference image\'s inner fill contour');
  assert.match(pack.svg, /M 82\.8 8 L 94\.5 9\.5 L 104\.3 15\.7/, 'top silhouette should follow the supplied reference');
  assert.match(pack.svg, /L 162\.1 70\.4 L 171\.1 70\.4 L 175 73\.1/, 'right side tuft should follow the supplied reference');
  assert.match(pack.svg, /L 5\.4 75\.8 L 5 70\.7 L 10\.9 66\.9 L 28\.4 67\.6/, 'left side tuft should follow the supplied reference');
  assert.doesNotMatch(pack.svg, /stroke-width="5\.5"/, 'body should not flatten the hand-drawn outline into one fixed stroke width');
});

test('loads the vector pawo blobfish with DIY shapes, blink eyes and the shared language pack', () => {
  const pack = loadCharacterPack(charactersRoot, 'blobfish-pawo');

  assert.equal(pack.manifest.displayName, '水滴魚（趴窩）');
  assert.equal(pack.manifest.defaultLanguagePack, 'blobfish-zh-TW');
  assert.equal(pack.settingsCopy.pageTitle, '水滴魚（趴窩）');
  assert.equal(pack.manifest.diy.enabled, true);
  assert.ok(pack.manifest.diy.shapes.body.length >= 3);
  assert.ok(pack.manifest.diy.shapes.fins.length >= 3);
  assert.match(pack.svg, /class="body-shape"/);
  assert.match(pack.svg, /class="eye eye-left"/);
  assert.doesNotMatch(pack.svg, /<image\b/, 'the 2D pawo character must remain editable vector art');
  assert.match(pack.styles.find((style) => style.path.endsWith('blink.css')).css, /\.eye\.is-blinking/);
});

test('loads the 3D pawo source as a bounded local WebP with blink overlays', () => {
  const pack = loadCharacterPack(charactersRoot, 'blobfish-3d-pawo');

  assert.equal(pack.manifest.displayName, '水滴魚（3D趴窩）');
  assert.equal(pack.manifest.defaultLanguagePack, 'blobfish-zh-TW');
  assert.equal(pack.settingsCopy.pageTitle, '水滴魚（3D趴窩）');
  assert.equal(pack.manifest.diy, undefined);
  assert.match(pack.svg, /href="data:image\/webp;base64,/);
  assert.doesNotMatch(pack.svg, /pack-image:/);
  assert.match(pack.svg, /class="eye eye-left"/);
  assert.match(pack.styles.find((style) => style.path.endsWith('blink.css')).css, /blobfish-3d-pawo-blink/);
  assert.ok(Buffer.byteLength(pack.svg) < 512 * 1024);
});

test('rejects invalid ids and paths outside the pack root', () => {
  assert.throws(() => loadCharacterPack(charactersRoot, '../blobfish'), /Invalid character pack id/);
  assert.throws(() => assertInside(charactersRoot, '../outside'), /escapes its root/);
});

test('legacy character settings copy remains valid without greeting labels', () => {
  const copy = { ...loadCharacterPack(charactersRoot, 'blobfish').settingsCopy };
  delete copy.greetingTitle;
  delete copy.greetingHint;
  assert.doesNotThrow(() => validateSettingsCopy(copy));
});

test('all vector blobfish packs ship DIY shape presets and non-vector characters do not', () => {
  for (const id of ['blobfish', 'blobfish-wotou', 'blobfish-pawo']) {
    const { manifest } = loadCharacterPack(charactersRoot, id);
    assert.equal(manifest.diy.enabled, true, `${id} should opt into DIY`);
    assert.ok(manifest.diy.shapes.body.length >= 2, `${id} needs body presets`);
    assert.ok(manifest.diy.shapes.fins.length >= 2, `${id} needs fin presets`);
    assert.equal(manifest.diy.shapes.body[0].id, 'default', `${id} must lead with its own shape`);
    assert.equal(manifest.diy.shapes.fins[0].id, 'default', `${id} must lead with its own fins`);
  }

  assert.equal(loadCharacterPack(charactersRoot, 'grass-buddy').manifest.diy, undefined);
  assert.equal(loadCharacterPack(charactersRoot, 'blobfish-3d-pawo').manifest.diy, undefined);
});

test('DIY presets reject anything that is not plain path data', () => {
  const validShapes = { body: [{ id: 'default', label: '圆润', d: 'M 0 0 L 10 10 Z' }] };

  assert.doesNotThrow(() => validateDiy({ enabled: true }));
  assert.doesNotThrow(() => validateDiy({ enabled: true, shapes: validShapes }));
  assert.throws(() => validateDiy({ enabled: 'yes' }), /boolean enabled/);
  assert.throws(() => validateDiy({ enabled: true, shapes: { tail: [] } }), /Unsupported diy shape group/);
  assert.throws(
    () => validateDiy({ enabled: true, shapes: { body: [{ id: 'x', label: 'x', d: 'url(#evil)' }] } }),
    /not SVG path data/,
  );
  assert.throws(
    () => validateDiy({ enabled: true, shapes: { fins: [{ id: 'x', label: 'x', left: 'M 0 0 Z' }] } }),
    /fins\[0\]\.right/,
  );
  assert.throws(
    () => validateDiy({
      enabled: true,
      shapes: { body: [{ id: 'a', label: 'a', d: 'M 0 0 Z' }, { id: 'a', label: 'b', d: 'M 1 1 Z' }] },
    }),
    /duplicate id/,
  );
});

test('a character manifest with a broken DIY block fails to load', () => {
  const manifest = loadCharacterPack(charactersRoot, 'blobfish').manifest;

  assert.doesNotThrow(() => validateManifest(manifest, 'blobfish'));
  assert.throws(
    () => validateManifest({ ...manifest, diy: { enabled: true, shapes: { body: [] } } }, 'blobfish'),
    /must list 1-12 options/,
  );
});

test('embedded character images accept only a small declared PNG or WebP set', () => {
  assert.doesNotThrow(() => validateEmbeddedImages({ character: 'art/character.webp' }));
  assert.throws(() => validateEmbeddedImages({}), /1-4 images/);
  assert.throws(() => validateEmbeddedImages({ Character: 'art/character.webp' }), /Invalid embedded image id/);
  assert.throws(() => validateEmbeddedImages({ character: 'art/character.svg' }), /PNG or WebP/);
});
