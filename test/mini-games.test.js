const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');

const { GAMES, RPS_MOVES, RIDDLES, checkRiddle, pickRiddle, playDice, playRps } = require('../src/core/mini-games');
const { loadAccessoryCatalog } = require('../src/core/accessory-loader');

const accessoriesRoot = path.join(__dirname, '..', 'src', 'packs', 'accessories');

// Feeds a fixed sequence to the random source so an outcome can be pinned.
function seq(values) {
  let i = 0;
  return () => values[Math.min(values.length - 1, i++)];
}

test('rock-paper-scissors judges every pairing correctly', () => {
  // The fish move is picked from RPS_MOVES by index; 0=rock, 1=scissors, 2=paper.
  assert.equal(playRps('rock', seq([1 / 3])).result, 'win', 'rock beats scissors');
  assert.equal(playRps('rock', seq([2 / 3])).result, 'lose', 'rock loses to paper');
  assert.equal(playRps('rock', seq([0])).result, 'draw', 'rock ties rock');
  assert.equal(playRps('scissors', seq([2 / 3])).result, 'win', 'scissors beats paper');
  assert.equal(playRps('paper', seq([0])).result, 'win', 'paper beats rock');
  assert.equal(playRps('nope'), null, 'an unknown move is rejected');
});

test('every rps outcome comes with a face the wardrobe actually ships', () => {
  const faces = new Set(loadAccessoryCatalog(accessoriesRoot).filter((a) => a.slot === 'face').map((a) => a.id));
  for (const move of RPS_MOVES) {
    const out = playRps(move.id, () => 0);
    assert.ok(out.reply.length > 0);
    assert.ok(faces.has(out.face), `${out.result} uses ${out.face}, missing from the wardrobe`);
  }
});

test('dice big/small resolves against the roll, with seven as the house', () => {
  // random returns r; dice value = 1 + floor(r*6). r=0 -> 1, r=0.9 -> 6.
  const small = playDice('small', seq([0, 0])); // 1 + 1 = 2 -> small
  assert.deepEqual(small.dice, [1, 1]);
  assert.equal(small.size, 'small');
  assert.equal(small.won, true);

  const big = playDice('big', seq([0.9, 0.9])); // 6 + 6 = 12 -> big
  assert.equal(big.size, 'big');
  assert.equal(big.won, true);

  const seven = playDice('big', seq([0.9, 0.1])); // 6 + 1 = 7 -> house
  assert.equal(seven.size, 'seven');
  assert.equal(seven.won, false, 'a seven never pays out the player');

  assert.equal(playDice('middle'), null, 'an invalid bet is rejected');
});

test('a riddle knows its right answer and reacts accordingly', () => {
  const riddle = pickRiddle(() => 0);
  assert.ok(Array.isArray(riddle.options) && riddle.options.length >= 2);

  const right = checkRiddle(riddle, riddle.answer, () => 0);
  assert.equal(right.correct, true);
  assert.equal(right.face, 'face-star-eye');

  const wrongIndex = (riddle.answer + 1) % riddle.options.length;
  const wrong = checkRiddle(riddle, wrongIndex, () => 0);
  assert.equal(wrong.correct, false);
  assert.match(wrong.reply, new RegExp(riddle.reveal.slice(0, 4)), 'a wrong answer reveals the solution');
});

test('every bundled riddle is answerable and its answer is in range', () => {
  assert.ok(RIDDLES.length >= 4);
  for (const riddle of RIDDLES) {
    assert.ok(riddle.answer >= 0 && riddle.answer < riddle.options.length, `${riddle.question} has a bad answer index`);
    assert.ok(riddle.options.length >= 2 && riddle.options.length <= 4);
  }
});

test('the game roster matches what the dialogue pack can launch', () => {
  assert.deepEqual([...GAMES].sort(), ['dice', 'riddle', 'rps']);
});
