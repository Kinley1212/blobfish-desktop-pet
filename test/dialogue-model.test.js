const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');

const {
  getNode,
  listOpeners,
  pickOpenerId,
  resolveChoice,
  validateDialogue,
} = require('../src/core/dialogue-model');
const { loadDialoguePack, loadDialoguePackSafe } = require('../src/core/dialogue-loader');
const { loadAccessoryCatalog } = require('../src/core/accessory-loader');

const dialoguesRoot = path.join(__dirname, '..', 'src', 'packs', 'dialogues');
const accessoriesRoot = path.join(__dirname, '..', 'src', 'packs', 'accessories');

function samplePack() {
  return {
    nodes: {
      hi: {
        opener: true,
        prompt: '你戳我干嘛。',
        options: [
          { label: '看看你', reply: '看够了没。', face: 'face-side-eye' },
          { label: '聊会儿', reply: '行吧。', face: 'face-blank', next: 'chat' },
        ],
      },
      chat: {
        prompt: '说点什么。',
        options: [{ label: '夸夸你', reply: '继续。', face: 'face-love' }],
      },
    },
  };
}

test('a well-formed pack validates and exposes its openers', () => {
  const pack = samplePack();
  assert.equal(validateDialogue(pack), pack);
  assert.deepEqual(listOpeners(pack), ['hi']);
  assert.equal(getNode(pack, 'chat').prompt, '说点什么。');
  assert.equal(getNode(pack, 'nope'), null);
});

test('choosing resolves to a reaction and either branches or ends', () => {
  const pack = samplePack();

  const branch = resolveChoice(pack, 'hi', 1);
  assert.deepEqual(branch, { reply: '行吧。', face: 'face-blank', nextId: 'chat', ended: false });

  const leaf = resolveChoice(pack, 'hi', 0);
  assert.deepEqual(leaf, { reply: '看够了没。', face: 'face-side-eye', nextId: null, ended: true });

  assert.equal(resolveChoice(pack, 'hi', 9), null, 'an out-of-range option resolves to nothing');
  assert.equal(resolveChoice(pack, 'ghost', 0), null, 'a missing node resolves to nothing');
});

test('an opener is always one of the flagged nodes', () => {
  const pack = {
    nodes: {
      a: { opener: true, prompt: 'a', options: [{ label: 'x' }] },
      b: { prompt: 'b', options: [{ label: 'y' }] },
      c: { opener: true, prompt: 'c', options: [{ label: 'z' }] },
    },
  };
  assert.equal(pickOpenerId(pack, () => 0), 'a');
  assert.equal(pickOpenerId(pack, () => 0.99999), 'c', 'a roll near 1 still lands on a real opener');
});

test('validation rejects the ways a pack can be broken', () => {
  assert.throws(() => validateDialogue(null), /must be an object/);
  assert.throws(() => validateDialogue({ nodes: {} }), /1-200 nodes/);
  assert.throws(
    () => validateDialogue({ nodes: { a: { prompt: 'a', options: [{ label: 'x' }] } } }),
    /at least one opener/,
  );
  assert.throws(
    () => validateDialogue({ nodes: { a: { opener: true, prompt: '', options: [{ label: 'x' }] } } }),
    /needs a short prompt/,
  );
  assert.throws(
    () => validateDialogue({ nodes: { a: { opener: true, prompt: 'a', options: [] } } }),
    /1-4 options/,
  );
  assert.throws(
    () => validateDialogue({ nodes: { a: { opener: true, prompt: 'a', options: [{ label: 'x', next: 'gone' }] } } }),
    /points to a missing node/,
  );
  assert.throws(
    () => validateDialogue({ nodes: { a: { opener: true, prompt: 'a', options: [{ label: 'x', face: 'crown' }] } } }),
    /face must be a face id/,
  );
});

test('the bundled blobfish dialogue pack loads and stays self-consistent', () => {
  const pack = loadDialoguePack(dialoguesRoot, 'blobfish-zh-TW');
  assert.ok(listOpeners(pack).length >= 3, 'a real conversation needs several openers');

  // Every face a choice can trigger must actually exist in the wardrobe, or
  // the reaction would silently do nothing.
  const faces = new Set(loadAccessoryCatalog(accessoriesRoot).filter((item) => item.slot === 'face').map((item) => item.id));
  for (const id of Object.keys(pack.nodes)) {
    for (const option of pack.nodes[id].options) {
      if (option.face) assert.ok(faces.has(option.face), `${id} uses ${option.face}, which is not a bundled expression`);
    }
  }
});

test('a missing or invalid dialogue pack is treated as no chat rather than a crash', () => {
  assert.equal(loadDialoguePackSafe(dialoguesRoot, 'does-not-exist'), null);
  assert.throws(() => loadDialoguePack(dialoguesRoot, '../secret'), /Invalid dialogue pack id/);
});
