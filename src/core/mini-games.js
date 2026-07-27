// Small games the fish can play inside the chat window. Each one is pure: given
// the player's choice and a random source, it returns what the fish did, who
// won, a line to say and an expression to wear. Keeping the logic here (not in
// the window) means it is testable and the window only draws.
(function (root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.miniGames = api;
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  function pick(list, random) {
    return list[Math.min(list.length - 1, Math.floor(random() * list.length))];
  }

  // --- 猜拳 -----------------------------------------------------------------
  const RPS_MOVES = Object.freeze([
    Object.freeze({ id: 'rock', label: '✊ 石头', beats: 'scissors' }),
    Object.freeze({ id: 'scissors', label: '✌️ 剪刀', beats: 'paper' }),
    Object.freeze({ id: 'paper', label: '🖐 布', beats: 'rock' }),
  ]);

  const RPS_LINES = Object.freeze({
    win: Object.freeze({ replies: ['……哼，让你了。', '运气而已。别得意。', '再来，我不信。'], face: 'face-annoyed' }),
    lose: Object.freeze({ replies: ['嘿，我赢了。', '看到没，这就是实力。', '菜。'], face: 'face-proud' }),
    draw: Object.freeze({ replies: ['……想到一块去了。', '平手。再来。', '英雄所见略同？'], face: 'face-side-eye' }),
  });

  function playRps(playerMoveId, random = Math.random) {
    const player = RPS_MOVES.find((move) => move.id === playerMoveId);
    if (!player) return null;
    const fish = pick(RPS_MOVES, random);

    let result;
    if (player.id === fish.id) result = 'draw';
    else if (player.beats === fish.id) result = 'win';
    else result = 'lose';

    const line = RPS_LINES[result];
    return {
      fishMove: fish,
      result,
      reply: pick(line.replies, random),
      face: line.face,
    };
  }

  // --- 猜大小 ---------------------------------------------------------------
  // Two dice; 3-6 is small, 8-11 is big, 7 is the house (fish) win — classic
  // sic bo feel, and it gives the fish a cheeky edge.
  function playDice(bet, random = Math.random) {
    if (bet !== 'big' && bet !== 'small') return null;
    const a = 1 + Math.floor(random() * 6);
    const b = 1 + Math.floor(random() * 6);
    const total = a + b;

    let size;
    if (total <= 6) size = 'small';
    else if (total >= 8) size = 'big';
    else size = 'seven';

    const won = size === bet;
    let reply;
    let face;
    if (size === 'seven') {
      reply = pick(['七点，归我。运气不好吧你。', '哈，豹子七，我赢。'], random);
      face = 'face-teasing';
    } else if (won) {
      reply = pick(['……真让你猜中了。', '算你厉害。', '哼，蒙对了。'], random);
      face = 'face-shocked';
    } else {
      reply = pick(['猜错咯～', '差一点？没有的事。', '再想想。'], random);
      face = 'face-smug';
    }
    return { dice: [a, b], total, size, won, reply, face };
  }

  // --- 脑筋急转弯 -----------------------------------------------------------
  const RIDDLES = Object.freeze([
    Object.freeze({
      question: '什么鱼没有骨头，还整天摆臭脸？',
      options: Object.freeze(['金鱼', '水滴鱼', '章鱼']),
      answer: 1,
      reveal: '……说的就是我。谢谢。',
    }),
    Object.freeze({
      question: '什么东西越洗越脏？',
      options: Object.freeze(['衣服', '水', '碗']),
      answer: 1,
      reveal: '水。洗什么都把自己弄脏。',
    }),
    Object.freeze({
      question: '一年里哪个月睡得最少？',
      options: Object.freeze(['二月', '十二月', '看心情']),
      answer: 0,
      reveal: '二月呀，天数最少。',
    }),
    Object.freeze({
      question: '什么帽子摘不下来？',
      options: Object.freeze(['安全帽', '瓶盖', '螺丝帽']),
      answer: 2,
      reveal: '螺丝帽。你试试摘。',
    }),
    Object.freeze({
      question: '什么越多，你反而越看不清？',
      options: Object.freeze(['光', '雾', '钱']),
      answer: 1,
      reveal: '雾。钱哪会嫌多。',
    }),
    Object.freeze({
      question: '书店里买不到什么书？',
      options: Object.freeze(['旧书', '遗书', '教科书']),
      answer: 1,
      reveal: '遗书。这个真买不着。',
    }),
  ]);

  function pickRiddle(random = Math.random) {
    return pick(RIDDLES, random);
  }

  function checkRiddle(riddle, optionIndex, random = Math.random) {
    if (!riddle || typeof riddle.answer !== 'number') return null;
    const correct = optionIndex === riddle.answer;
    return {
      correct,
      reply: correct
        ? pick(['……居然答对了。', '嚯，有点东西。', '算你聪明。'], random)
        : pick([`不对。${riddle.reveal}`, `错啦。${riddle.reveal}`], random),
      reveal: riddle.reveal,
      face: correct ? 'face-star-eye' : 'face-teasing',
    };
  }

  const GAMES = Object.freeze(['rps', 'dice', 'riddle']);

  return Object.freeze({
    GAMES,
    RPS_MOVES,
    RIDDLES,
    checkRiddle,
    pickRiddle,
    playDice,
    playRps,
  });
}));
