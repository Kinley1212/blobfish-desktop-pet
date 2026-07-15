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
  for (const action of REQUIRED_ACTIONS) {
    assert.equal(typeof pack.manifest.actions[action], 'string');
  }
});

test('rejects invalid ids and paths outside the pack root', () => {
  assert.throws(() => loadCharacterPack(charactersRoot, '../blobfish'), /Invalid character pack id/);
  assert.throws(() => assertInside(charactersRoot, '../outside'), /escapes its root/);
});
