const { getNode, pickOpenerId, resolveChoice } = globalThis.dialogueModel;
const { applyDiyToSvg } = globalThis.diyModel;
const { applyAccessoriesToSvg, normalizeAccessories } = globalThis.accessoryModel;

const promptEl = document.getElementById('prompt');
const optionsEl = document.getElementById('options');
const closeEl = document.getElementById('close');
const avatarEl = document.getElementById('avatar');

// After a topic wraps up, the fish just moves on to the next one on its own.
const NEXT_TOPIC_DELAY_MS = 1400;

let pack = null;
let currentNodeId = null;

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
  promptEl.textContent = '……我现在不太想说话。';
  optionsEl.replaceChildren();
  currentNodeId = null;
}

function renderNode(nodeId) {
  const node = getNode(pack, nodeId);
  if (!node) {
    startFresh();
    return;
  }
  currentNodeId = nodeId;
  promptEl.textContent = node.prompt;
  optionsEl.replaceChildren();

  node.options.forEach((option, index) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'chat-option';
    button.textContent = option.label;
    button.addEventListener('click', () => choose(index));
    optionsEl.appendChild(button);
  });
}

function choose(index) {
  const outcome = resolveChoice(pack, currentNodeId, index);
  if (!outcome) return;

  // The fish reacts right here in the window — its face changes and it says
  // its reply — and the desktop pet mirrors the same expression.
  showAvatarFace(outcome.face);
  if (outcome.face) window.dialogueAPI.react({ face: outcome.face });
  if (outcome.reply) promptEl.textContent = outcome.reply;

  for (const button of optionsEl.querySelectorAll('button')) button.disabled = true;
  // A branch keeps going; a finished topic rolls straight into a new one after
  // a slightly longer beat, so the reply has time to land.
  if (outcome.ended) {
    setTimeout(startFresh, NEXT_TOPIC_DELAY_MS);
  } else {
    setTimeout(() => renderNode(outcome.nextId), outcome.reply ? 950 : 200);
  }
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
    buildAvatar();
    pack = loadedPack;
    startFresh();
  })
  .catch(() => {
    promptEl.textContent = '……出了点问题，改天聊。';
  });
