const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');

const { REQUIRED_ACTIONS, assertInside, loadCharacterPack, validateSettingsCopy } = require('../src/core/pack-loader');

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

test('rejects invalid ids and paths outside the pack root', () => {
  assert.throws(() => loadCharacterPack(charactersRoot, '../blobfish'), /Invalid character pack id/);
  assert.throws(() => assertInside(charactersRoot, '../outside'), /escapes its root/);
});

test('legacy character settings copy remains valid without 2.3 greeting labels', () => {
  const copy = { ...loadCharacterPack(charactersRoot, 'blobfish').settingsCopy };
  delete copy.greetingTitle;
  delete copy.greetingHint;
  assert.doesNotThrow(() => validateSettingsCopy(copy));
});
