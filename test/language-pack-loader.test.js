const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { loadLanguagePack } = require('../src/core/language-pack-loader');

const languagesRoot = path.join(__dirname, '..', 'src', 'packs', 'languages');

const ORIGINAL_CLICK = [
  '痛痛痛!!', '幹嘛啦!', '欺負魚喔', '哼,不理你了', '再點我要生氣了', '唉唷!', '住手啦!', '很痛耶!',
];
const ORIGINAL_IDLE = [
  '肚子餓了...', '今天天氣不錯', '要不要休息一下', '游泳好累喔', '主人在忙什麼呢', '想睡覺了',
  '水滴魚也是有尊嚴的', '別再甩我了啦', '今天也要加油喔', '發呆中', '有沒有人可以陪我聊天',
  '我是水滴魚,不是普通的魚', '泡泡都被我吐光了', '深海的家好想念', '主人今天喝水了嗎',
  '電腦螢幕好亮喔', '我也想要放假', '鰭有點痠', '誰把我丟到這裡的', '其實我很可愛的', '嘟嘟嘟',
  '眼睛好像有點花', '該不會忘記我了吧', '游來游去也是一種運動', '心情不錯', '今天心情普通',
  '想吃點什麼呢', '主人辛苦了', '我在想事情', '別小看水滴魚', '喘口氣',
  '今天的雲很好看(如果我看得到的話)', '滑鼠不要靠近我', '我在思考鹹魚的意義',
];
const ORIGINAL_SCHEDULE = [
  '主人您辛苦了，您又工作了半小時。',
  '主人還有五分鐘就可以去吃飯啦，您辛苦啦。',
  '主人還有半個鐘就下班啦，主人今天太棒啦！',
  '主人還有五分鐘就下班啦，可以開始關閉軟件啦，記得先關梯子再關Claude喲。主人{farewell}～',
];

test('language pack preserves every original phrase verbatim and keeps additions separate', () => {
  const pack = loadLanguagePack(languagesRoot, 'blobfish-zh-TW');
  const originals = pack.phrases.filter((phrase) => phrase.sourceGroup === 'original');
  const additions = pack.phrases.filter((phrase) => phrase.sourceGroup === 'additions');

  assert.deepEqual(originals.filter((phrase) => phrase.event === 'interaction.click').map((phrase) => phrase.text), ORIGINAL_CLICK);
  assert.deepEqual(originals.filter((phrase) => phrase.event === 'idle.chatter').map((phrase) => phrase.text), ORIGINAL_IDLE);
  assert.deepEqual(originals.filter((phrase) => phrase.event.startsWith('schedule.')).map((phrase) => phrase.text), ORIGINAL_SCHEDULE);
  assert.equal(originals.length, 46);
  assert.ok(additions.length > 0);
  assert.ok(additions.every((phrase) => phrase.sourcePath.startsWith('additions/')));
});

test('language pack contains dedicated 3% and 2% battery phrases', () => {
  const pack = loadLanguagePack(languagesRoot, 'blobfish-zh-TW');
  const batteryPhrases = pack.phrases.filter((phrase) => phrase.event === 'system.battery');
  assert.equal(batteryPhrases.filter((phrase) => phrase.conditions.batteryEquals === 3).length, 2);
  assert.equal(batteryPhrases.filter((phrase) => phrase.conditions.batteryEquals === 2).length, 2);
});

test('language additions include multiple farewell lines for graceful quit', () => {
  const pack = loadLanguagePack(languagesRoot, 'blobfish-zh-TW');
  const farewellPhrases = pack.phrases.filter((phrase) => phrase.event === 'interaction.goodbye');
  assert.ok(farewellPhrases.length >= 4);
  assert.ok(farewellPhrases.every((phrase) => phrase.sourcePath.startsWith('additions/')));
});

test('right-click, pause and resume phrases are additive interactions', () => {
  const pack = loadLanguagePack(languagesRoot, 'blobfish-zh-TW');
  for (const eventName of ['interaction.menuOpen', 'interaction.paused', 'interaction.resumed']) {
    const phrases = pack.phrases.filter((phrase) => phrase.event === eventName);
    assert.ok(phrases.length >= 3);
    assert.ok(phrases.every((phrase) => phrase.sourceGroup === 'additions'));
    assert.ok(phrases.every((phrase) => phrase.sourcePath === 'additions/interactions.json'));
  }
});
