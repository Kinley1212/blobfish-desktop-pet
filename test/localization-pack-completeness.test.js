const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { loadDialoguePack } = require('../src/core/dialogue-loader');
const { listOpeners } = require('../src/core/dialogue-model');
const { loadLanguagePack } = require('../src/core/language-pack-loader');
const { loadAccessoryCatalog } = require('../src/core/accessory-loader');

const root = path.join(__dirname, '..', 'src', 'packs');
const packIds = fs.readdirSync(path.join(root, 'languages'), { withFileTypes: true })
  .filter((entry) => entry.isDirectory()).map((entry) => entry.name);

function dialogueText(pack) {
  return Object.values(pack.nodes).flatMap((node) => [node.prompt,
    ...node.options.flatMap((option) => [option.label, option.reply || ''])]).join('\n');
}

test('every bundled language has its own complete, reachable interactive dialogue', () => {
  const baseline = loadDialoguePack(path.join(root, 'dialogues'), 'blobfish-zh-TW');
  const expectedNodes = Object.keys(baseline.nodes).sort();
  for (const id of packIds) {
    const pack = loadDialoguePack(path.join(root, 'dialogues'), id);
    assert.deepEqual(Object.keys(pack.nodes).sort(), expectedNodes, `${id}: same topic coverage`);
    assert.deepEqual(listOpeners(pack).sort(), listOpeners(baseline).sort(), `${id}: same opening topics`);
    const reachable = new Set();
    const visit = (nodeId) => {
      if (reachable.has(nodeId)) return;
      reachable.add(nodeId);
      for (const option of pack.nodes[nodeId].options) if (option.next) visit(option.next);
    };
    listOpeners(pack).forEach(visit);
    assert.equal(reachable.size, expectedNodes.length, `${id}: no unreachable content`);
    const games = new Set();
    for (const [nodeId, node] of Object.entries(pack.nodes)) {
      assert.equal(node.options.length, baseline.nodes[nodeId].options.length, `${id}/${nodeId}: choices`);
      node.options.forEach((option, index) => {
        const expected = baseline.nodes[nodeId].options[index];
        assert.equal(option.next, expected.next, `${id}/${nodeId}: branch`);
        assert.equal(option.game, expected.game, `${id}/${nodeId}: game`);
        if (expected.reply) assert.ok(option.reply?.trim(), `${id}/${nodeId}: missing reply`);
        if (option.game) games.add(option.game);
      });
    }
    assert.deepEqual([...games].sort(), ['dice', 'riddle', 'rps'], id);
  }
});

test('dialogue reactions exist and grass buddy uses only its restrained native expressions', () => {
  const faces = new Set(loadAccessoryCatalog(path.join(root, 'accessories'))
    .filter((item) => item.slot === 'face').map((item) => item.id));
  const grassFaces = new Set(['face-grass-calm', 'face-grass-happy', 'face-grass-worried']);
  for (const id of packIds) {
    const pack = loadDialoguePack(path.join(root, 'dialogues'), id);
    for (const node of Object.values(pack.nodes)) {
      for (const option of node.options) {
        if (option.face) assert.ok(faces.has(option.face), `${id}: unknown ${option.face}`);
        if (id.startsWith('grass-buddy')) assert.ok(grassFaces.has(option.face), `${id}: incompatible ${option.face}`);
      }
    }
  }
  const grass = dialogueText(loadDialoguePack(path.join(root, 'dialogues'), 'grass-buddy-zh-CN'));
  assert.doesNotMatch(grass, /水滴魚|水滴鱼|鱼鳍|魚鰭|游泳/);
});

test('all language packs cover the same runtime events without empty text or duplicate IDs', () => {
  const baseline = loadLanguagePack(path.join(root, 'languages'), 'blobfish-zh-TW');
  const events = [...new Set(baseline.phrases.map((phrase) => phrase.event))].sort();
  for (const id of packIds) {
    const pack = loadLanguagePack(path.join(root, 'languages'), id);
    assert.equal(new Set(pack.phrases.map((phrase) => phrase.id)).size, pack.phrases.length, id);
    assert.deepEqual([...new Set(pack.phrases.map((phrase) => phrase.event))].sort(), events, id);
    for (const phrase of pack.phrases) assert.ok(phrase.text.trim(), `${id}/${phrase.id}`);
    if (pack.manifest.locale === 'en') {
      assert.doesNotMatch(pack.phrases.map((phrase) => phrase.text).join('\n'), /[\u3400-\u9fff]/u, id);
      assert.doesNotMatch(dialogueText(loadDialoguePack(path.join(root, 'dialogues'), id)), /[\u3400-\u9fff]/u, id);
    }
  }
});

test('Traditional Chinese additions and dialogue do not regress to known simplified wording', () => {
  const pack = loadLanguagePack(path.join(root, 'languages'), 'blobfish-zh-TW');
  const text = pack.phrases.filter((phrase) => phrase.sourceGroup === 'additions')
    .map((phrase) => phrase.text).join('\n') + '\n'
    + dialogueText(loadDialoguePack(path.join(root, 'dialogues'), 'blobfish-zh-TW'));
  // Unambiguous simplified forms from the previously mixed-language content.
  // Avoid ambiguous shared characters (e.g. 只/面), which are valid in both scripts.
  assert.doesNotMatch(text, /[这来没还开关设时话鱼们会欢过见终于觉气对点让别样满经动应线钟软页显选谅谎够爱声听亲]/u);
  assert.match(text, /今天也要開始了嗎/);
  assert.match(text, /設定裡應該沒有海水/);
});
