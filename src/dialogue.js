const { getNode, pickOpenerId, resolveChoice } = globalThis.dialogueModel;
const miniGames = globalThis.miniGames;
const { applyDiyToSvg } = globalThis.diyModel;
const { applyAccessoriesToSvg, normalizeAccessories } = globalThis.accessoryModel;
const uiI18n = globalThis.uiI18n;

const promptEl = document.getElementById('prompt');
const optionsEl = document.getElementById('options');
const closeEl = document.getElementById('close');
const avatarEl = document.getElementById('avatar');

// After a topic wraps up, the fish just moves on to the next one on its own.
const NEXT_TOPIC_DELAY_MS = 1400;

let pack = null;
let currentNodeId = null;
let uiLocale = uiI18n.DEFAULT_LOCALE;

// The fish drawn inside the window: the user's own character, shaped and
// dressed as they left it, whose expression follows the conversation.
let character = null;
let avatarSvg = null;
let faceResetTimer = null;

function renderAvatar(faceOverride) {
  if (!avatarSvg || !character) return;
  const spec = normalizeAccessories(character.worn);
  if (faceOverride) spec.equipped.face = faceOverride;
  applyAccessoriesToSvg(avatarSvg, character.manifest, character.accessories, spec);
}

// Wear an expression for a beat, then fall back to the resting look.
function showAvatarFace(faceId) {
  clearTimeout(faceResetTimer);
  if (!faceId) {
    renderAvatar(null);
    return;
  }
  renderAvatar(faceId);
  faceResetTimer = setTimeout(() => renderAvatar(null), 2600);
}

function buildAvatar() {
  if (!character) return;
  const parsed = new DOMParser().parseFromString(character.svg, 'image/svg+xml');
  if (parsed.querySelector('parsererror')) return;
  parsed.querySelectorAll('script, foreignObject, iframe, object, embed').forEach((node) => node.remove());
  // A resting portrait shouldn't cry; tears belong to the punch reaction.
  parsed.querySelectorAll('.tears, .tear').forEach((node) => node.remove());

  avatarSvg = document.importNode(parsed.documentElement, true);
  avatarEl.replaceChildren(avatarSvg);
  applyDiyToSvg(avatarSvg, character.customization, character.manifest);
  renderAvatar(null);
}

function noPack() {
  promptEl.textContent = uiLocale === 'en' ? '…I do not feel like talking right now.' : '……我现在不太想说话。';
  optionsEl.replaceChildren();
  currentNodeId = null;
}

// Draws a set of buttons; each choice carries its own click handler. Used both
// for scripted nodes and for the free-form buttons a mini-game needs.
function setChoices(choices) {
  optionsEl.replaceChildren();
  for (const choice of choices) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'chat-option';
    button.textContent = choice.label;
    button.addEventListener('click', choice.onClick);
    optionsEl.appendChild(button);
  }
}

// The fish reacts in the window — its face changes and it says the line — and
// the desktop pet mirrors the same expression.
function reactAndSay(text, face) {
  showAvatarFace(face);
  if (face) window.dialogueAPI.react({ face });
  if (text) promptEl.textContent = text;
}

function renderNode(nodeId) {
  const node = getNode(pack, nodeId);
  if (!node) {
    startFresh();
    return;
  }
  currentNodeId = nodeId;
  promptEl.textContent = node.prompt;
  setChoices(node.options.map((option, index) => ({ label: option.label, onClick: () => choose(index) })));
}

function choose(index) {
  const outcome = resolveChoice(pack, currentNodeId, index);
  if (!outcome) return;

  reactAndSay(outcome.reply, outcome.face);
  for (const button of optionsEl.querySelectorAll('button')) button.disabled = true;

  if (outcome.game) {
    setTimeout(() => runGame(outcome.game), outcome.reply ? 700 : 350);
  } else if (outcome.ended) {
    // A finished topic rolls straight into a new one after a beat.
    setTimeout(startFresh, NEXT_TOPIC_DELAY_MS);
  } else {
    setTimeout(() => renderNode(outcome.nextId), outcome.reply ? 950 : 200);
  }
}

// --- mini-games ----------------------------------------------------------
// Each game reuses the same window: a prompt plus buttons, with the fish
// emoting the outcome. After a round you can replay, switch games or go back
// to talking.

function afterRound(replay) {
  setChoices([
    { label: '再来一局', onClick: replay },
    { label: '换个游戏', onClick: () => renderNode('games') },
    { label: '不玩了', onClick: startFresh },
  ]);
}

function playRpsRound() {
  promptEl.textContent = '出什么？输了不许哭。';
  setChoices(miniGames.RPS_MOVES.map((move) => ({
    label: move.label,
    onClick: () => {
      const result = miniGames.playRps(move.id);
      reactAndSay(`我出${result.fishMove.label.slice(2)}。${result.reply}`, result.face);
      afterRound(playRpsRound);
    },
  })));
}

function playDiceRound() {
  promptEl.textContent = '猜大小。骰子要摇了。';
  setChoices([
    { label: '压大（8-11）', onClick: () => rollDice('big') },
    { label: '压小（3-6）', onClick: () => rollDice('small') },
  ]);
}

function rollDice(bet) {
  const result = miniGames.playDice(bet);
  reactAndSay(`🎲 ${result.dice[0]} + ${result.dice[1]} = ${result.total}。${result.reply}`, result.face);
  afterRound(playDiceRound);
}

function playRiddleRound() {
  const riddle = miniGames.pickRiddle();
  promptEl.textContent = riddle.question;
  setChoices(riddle.options.map((label, index) => ({
    label,
    onClick: () => {
      const result = miniGames.checkRiddle(riddle, index);
      reactAndSay(result.reply, result.face);
      afterRound(playRiddleRound);
    },
  })));
}

function runGame(gameId) {
  currentNodeId = null;
  if (gameId === 'rps') playRpsRound();
  else if (gameId === 'dice') playDiceRound();
  else if (gameId === 'riddle') playRiddleRound();
  else startFresh();
}

function startFresh() {
  if (!pack) {
    noPack();
    return;
  }
  showAvatarFace(null);
  const openerId = pickOpenerId(pack);
  if (openerId) renderNode(openerId);
  else noPack();
}

closeEl.addEventListener('click', () => window.dialogueAPI.close());

Promise.all([window.dialogueAPI.getPack(), window.dialogueAPI.getCharacter()])
  .then(([loadedPack, loadedCharacter]) => {
    character = loadedCharacter;
    uiLocale = uiI18n.applyDocument(document, character?.uiLocale);
    buildAvatar();
    pack = loadedPack;
    startFresh();
  })
  .catch(() => {
    promptEl.textContent = uiLocale === 'en' ? '…Something went wrong. Another time.' : '……出了点问题，改天聊。';
  });
