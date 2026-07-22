const pet = document.getElementById('pet');
const bubble = document.getElementById('bubble');
const taskBubble = document.getElementById('task-bubble');
const { buildCarouselLayout, nextTaskKey } = globalThis.taskCarouselModel;

const VELOCITY_WINDOW_MS = 300;
const BLINK_MIN_MS = 3500;
const BLINK_MAX_MS = 9000;
const BLINK_DURATION_MS = 180;
const DOUBLE_BLINK_CHANCE = 0.12;
const TASK_ROTATION_MS = 1900;
// Minimum cumulative pointer movement (px) before a press-and-move counts as
// a drag. Below this it's treated as a click even if the hand wasn't
// perfectly still between mousedown and mouseup.
const DRAG_THRESHOLD_PX = 4;
// If the pointer hasn't moved for at least this long before release, the
// hand had already come to a stop - treat the release as velocity-free.
const STILL_THRESHOLD_MS = 60;
// Petting = stroking back and forth over the pet. We look at horizontal
// hover motion within a short window and require a few direction reversals
// plus enough total travel, then cool down so it doesn't fire repeatedly.
const PETTING_WINDOW_MS = 900;
const PETTING_MIN_REVERSALS = 3;
const PETTING_MIN_TRAVEL_PX = 44;
const PETTING_COOLDOWN_MS = 2600;
const BLUSH_DURATION_MS = 2600;

let bubbleTimer = null;
let taskStatusTimer = null;
let taskRotationTimer = null;
let terminalTaskStatusUntil = 0;
let pendingTaskStatus;
let taskCarouselItems = [];
let currentTaskKey = null;
let lastTaskStatusSignature = null;
const taskCardNodes = new Map();
let hitTimer = null;
let bumpTimer = null;
let dragging = false;
let movedDuringDrag = false;
let dragDistance = 0;
let moveHistory = []; // recent { t, dx, dy } samples, used to estimate release velocity
let isHoveringPet = false; // cursor is currently resting on the pet
let pettingHistory = []; // recent hover-move samples, used to detect back-and-forth stroking
let pettingCooldownUntil = 0; // suppresses repeat petting reactions for a short while
let blushTimer = null;
let blinkTimer = null;
let speechActionTimer = null;
let characterManifest = null;
let petScale = 1;
let petTopOffset = null;

function applyPetLayout(layout = {}) {
  const nextTopOffset = Number(layout.topOffset);
  if (Number.isFinite(nextTopOffset)) petTopOffset = Math.max(0, nextTopOffset);
  if (Number.isFinite(petTopOffset)) {
    document.documentElement.style.setProperty('--pet-top', `${petTopOffset}px`);
  }
  if (layout.bubblePlacement === 'below' || layout.bubblePlacement === 'above') {
    bubble.dataset.placement = layout.bubblePlacement;
    taskBubble.dataset.placement = layout.bubblePlacement;
  }
}

function applyPetConfig(config = {}) {
  const nextScale = Number(config.scale);
  petScale = Number.isFinite(nextScale) ? Math.min(1.5, Math.max(0.65, nextScale)) : 1;
  applyPetLayout(config);
  if (!characterManifest) return;
  const width = characterManifest.size.width * petScale;
  const height = characterManifest.size.height * petScale;
  pet.style.width = `${width}px`;
  pet.style.height = `${height}px`;
  document.documentElement.style.setProperty('--pet-height', `${height}px`);
}

function sanitizeSvg(svgText) {
  const parser = new DOMParser();
  const documentNode = parser.parseFromString(svgText, 'image/svg+xml');
  if (documentNode.querySelector('parsererror')) {
    throw new Error('Character pack contains invalid SVG');
  }

  documentNode.querySelectorAll('script, foreignObject, iframe, object, embed').forEach((node) => node.remove());
  documentNode.querySelectorAll('*').forEach((node) => {
    for (const attribute of [...node.attributes]) {
      const name = attribute.name.toLowerCase();
      const value = attribute.value.trim();
      if (name.startsWith('on')) {
        node.removeAttribute(attribute.name);
      } else if ((name === 'href' || name === 'xlink:href') && !value.startsWith('#')) {
        node.removeAttribute(attribute.name);
      }
    }
  });

  return documentNode.documentElement.outerHTML;
}

function applyCharacterPack(pack) {
  clearTimeout(blinkTimer);
  const svg = sanitizeSvg(pack.svg);
  document.querySelectorAll('style[data-character-style]').forEach((element) => element.remove());

  characterManifest = pack.manifest;
  pet.dataset.character = pack.manifest.id;
  for (const style of pack.styles) {
    const styleElement = document.createElement('style');
    styleElement.dataset.characterStyle = style.path;
    styleElement.textContent = style.css;
    document.head.appendChild(styleElement);
  }
  pet.innerHTML = svg;
  applyPetConfig({ scale: petScale });
  scheduleBlink(300);
}

async function installCharacterPack() {
  applyCharacterPack(await window.petAPI.getCharacterPack());
}

function scheduleBlink(delayOverride) {
  clearTimeout(blinkTimer);
  const delay = Number.isFinite(delayOverride)
    ? delayOverride
    : BLINK_MIN_MS + Math.random() * (BLINK_MAX_MS - BLINK_MIN_MS);

  blinkTimer = setTimeout(() => {
    if (dragging || pet.classList.contains('hit') || pet.classList.contains('bump')) {
      scheduleBlink(900);
      return;
    }

    const eyes = [...pet.querySelectorAll('.eye')];
    if (eyes.length === 0) return;
    eyes.forEach((eye) => eye.classList.remove('is-blinking'));
    void pet.offsetWidth;
    eyes.forEach((eye) => eye.classList.add('is-blinking'));

    setTimeout(() => {
      eyes.forEach((eye) => eye.classList.remove('is-blinking'));
      if (Math.random() < DOUBLE_BLINK_CHANCE) {
        scheduleBlink(170);
      } else {
        scheduleBlink();
      }
    }, BLINK_DURATION_MS);
  }, delay);
}

function showBubble(text, duration) {
  bubble.textContent = text;
  bubble.style.opacity = '1';
  clearTimeout(bubbleTimer);
  bubbleTimer = setTimeout(() => {
    bubble.style.opacity = '0';
  }, duration);
}

function setDirection(dir) {
  pet.style.setProperty('--dir', dir >= 0 ? 1 : -1);
}

function applyAgentState(state) {
  const allowedMotions = new Set(['idle', 'roam', 'working', 'waiting']);
  pet.dataset.motion = allowedMotions.has(state.motion) ? state.motion : 'idle';
}

function isTerminalTaskState(state) {
  return state === 'completed' || state === 'ended' || state === 'failed';
}

function taskItemKey(item, index) {
  if (typeof item?.taskKey === 'string' && item.taskKey) return item.taskKey;
  return `${item?.provider || 'task'}:${item?.title || 'untitled'}:${index}`;
}

function normalizeTaskItems(status) {
  if (!status) return [];
  const source = Array.isArray(status.items) && status.items.length ? status.items : [status];
  const seen = new Set();
  return source.flatMap((item, index) => {
    if (!item || typeof item.title !== 'string') return [];
    const state = ['running', 'waiting', 'ended', 'completed', 'failed'].includes(item.state)
      ? item.state
      : 'running';
    const taskKey = taskItemKey(item, index);
    if (seen.has(taskKey)) return [];
    seen.add(taskKey);
    return [{
      taskKey,
      state,
      title: item.title.trim().slice(0, 120),
      provider: item.provider,
    }];
  }).filter((item) => item.title);
}

function taskStatusSignature(status, items) {
  if (!status) return 'none';
  return JSON.stringify({
    taskKey: taskItemKey(status, 0),
    state: status.state,
    title: status.title,
    items: items.map(({ taskKey, state, title }) => [taskKey, state, title]),
  });
}

function createTaskCard(taskKey) {
  const card = document.createElement('div');
  card.className = 'task-card';
  card.dataset.depth = 'hidden';
  card.dataset.taskKey = taskKey;

  const icon = document.createElement('span');
  icon.className = 'task-status-icon';
  icon.setAttribute('aria-hidden', 'true');
  const title = document.createElement('span');
  title.className = 'task-title';
  const count = document.createElement('span');
  count.className = 'task-count';
  count.hidden = true;
  card.append(icon, title, count);
  taskBubble.append(card);
  taskCardNodes.set(taskKey, card);
  return card;
}

function updateTaskCard(card, item, depth, position, total, visible) {
  card.dataset.state = item.state;
  card.dataset.depth = visible ? String(depth) : 'hidden';
  card.setAttribute('aria-hidden', depth === 0 ? 'false' : 'true');
  card.querySelector('.task-title').textContent = item.title;
  card.querySelector('.task-status-icon').textContent = item.state === 'completed'
    ? '✓'
    : item.state === 'ended'
      ? '•'
      : item.state === 'failed'
        ? '!'
        : item.state === 'waiting'
          ? '…'
          : '';
  const count = card.querySelector('.task-count');
  count.hidden = depth !== 0 || total <= 1;
  count.textContent = depth === 0 && total > 1 ? `${position}/${total}` : '';
}

function renderTaskCarousel() {
  clearTimeout(taskRotationTimer);
  if (taskCarouselItems.length === 0) {
    taskBubble.dataset.visible = 'false';
    taskBubble.removeAttribute('aria-label');
    document.body.classList.remove('has-task-bubble');
    for (const card of taskCardNodes.values()) card.remove();
    taskCardNodes.clear();
    currentTaskKey = null;
    return;
  }

  const layout = buildCarouselLayout(taskCarouselItems, currentTaskKey);
  const frontIndex = layout.frontIndex;
  currentTaskKey = layout.frontTaskKey;
  const activeKeys = new Set(taskCarouselItems.map((item) => item.taskKey));
  for (const [taskKey, card] of taskCardNodes) {
    if (!activeKeys.has(taskKey)) {
      card.remove();
      taskCardNodes.delete(taskKey);
    }
  }

  layout.entries.forEach(({ item, depth, visible }) => {
    const card = taskCardNodes.get(item.taskKey) || createTaskCard(item.taskKey);
    updateTaskCard(card, item, depth, layout.position, layout.total, visible);
  });

  const front = taskCarouselItems[frontIndex];
  const stateLabel = front.state === 'running'
    ? '进行中'
    : front.state === 'waiting'
      ? '等待确认'
      : front.state === 'completed'
        ? '已完成'
        : front.state === 'ended'
          ? '已结束'
          : '失败';
  taskBubble.dataset.visible = 'true';
  taskBubble.setAttribute(
    'aria-label',
    `${front.title}：${stateLabel}${layout.total > 1 ? `，第 ${layout.position} 个，共 ${layout.total} 个任务` : ''}`,
  );
  document.body.classList.add('has-task-bubble');

  if (taskCarouselItems.length > 1 && !isTerminalTaskState(front.state)) {
    taskRotationTimer = setTimeout(() => {
      currentTaskKey = nextTaskKey(taskCarouselItems, currentTaskKey);
      renderTaskCarousel();
    }, TASK_ROTATION_MS);
  }
}

function renderTaskStatus(status, options = {}) {
  const items = normalizeTaskItems(status);
  const signature = taskStatusSignature(status, items);
  const requestedTaskKey = items.find((item) => item.taskKey === status?.taskKey)?.taskKey
    || items[0]?.taskKey
    || null;
  if (!options.force && signature === lastTaskStatusSignature && requestedTaskKey === currentTaskKey) return;

  const terminalIncoming = isTerminalTaskState(status?.state);
  const current = taskCarouselItems.find((item) => item.taskKey === currentTaskKey);
  const failedStatusIsProtected = current?.state === 'failed' && Date.now() < terminalTaskStatusUntil;
  if (!options.force && failedStatusIsProtected && !terminalIncoming && status?.state !== 'waiting') {
    pendingTaskStatus = status;
    return;
  }

  clearTimeout(taskStatusTimer);
  clearTimeout(taskRotationTimer);
  terminalTaskStatusUntil = 0;
  pendingTaskStatus = undefined;
  lastTaskStatusSignature = signature;
  taskCarouselItems = items;

  currentTaskKey = requestedTaskKey;
  renderTaskCarousel();

  if (terminalIncoming) {
    const durationMs = status.state === 'failed' ? 3600 : 2800;
    terminalTaskStatusUntil = Date.now() + durationMs;
    taskStatusTimer = setTimeout(() => {
      terminalTaskStatusUntil = 0;
      const nextStatus = pendingTaskStatus !== undefined ? pendingTaskStatus : (status.next || null);
      pendingTaskStatus = undefined;
      renderTaskStatus(nextStatus, { force: true });
    }, durationMs);
  }
}

function triggerSpeechAction(action) {
  clearTimeout(speechActionTimer);
  pet.classList.remove('is-success', 'is-failed');
  if (action !== 'success' && action !== 'failed') return;
  void pet.offsetWidth;
  pet.classList.add(action === 'success' ? 'is-success' : 'is-failed');
  speechActionTimer = setTimeout(() => {
    pet.classList.remove('is-success', 'is-failed');
  }, action === 'success' ? 750 : 950);
}

function triggerPetAction(message = {}) {
  if (message.action !== 'exit') return;
  const requestedDuration = Number(message.durationMs);
  const durationMs = Number.isFinite(requestedDuration)
    ? Math.min(5000, Math.max(200, requestedDuration))
    : 1700;
  clearTimeout(blinkTimer);
  clearTimeout(hitTimer);
  clearTimeout(bumpTimer);
  clearTimeout(speechActionTimer);
  clearTimeout(taskStatusTimer);
  clearTimeout(taskRotationTimer);
  terminalTaskStatusUntil = 0;
  pendingTaskStatus = undefined;
  renderTaskStatus(null, { force: true });
  pet.classList.remove('hit', 'bump', 'dragging', 'is-success', 'is-failed', 'is-exiting');
  pet.style.setProperty('--exit-duration', `${durationMs}ms`);
  void pet.offsetWidth;
  pet.classList.add('is-exiting');
}

function triggerBump() {
  pet.classList.remove('bump');
  void pet.offsetWidth;
  pet.classList.add('bump');

  // Without this, 'bump' stays on the element forever after the first wall
  // hit. #pet.bump and #pet.hit have equal CSS specificity, and #pet.bump
  // is declared later in the stylesheet, so a stuck 'bump' class silently
  // wins the `animation` property over every future 'hit' click - the click
  // handler still fires and adds 'hit', but nothing visibly plays.
  clearTimeout(bumpTimer);
  bumpTimer = setTimeout(() => {
    pet.classList.remove('bump');
  }, 320);
}

function triggerBlush() {
  pet.classList.add('is-blushing');
  clearTimeout(blushTimer);
  blushTimer = setTimeout(() => {
    pet.classList.remove('is-blushing');
  }, BLUSH_DURATION_MS);
}

// Records a horizontal hover-move sample and decides whether the recent
// motion looks like stroking (enough back-and-forth reversals and travel).
// Returns true exactly once per gesture, then starts a cooldown.
function detectPetting(dx) {
  const now = performance.now();
  pettingHistory.push({ t: now, dx });
  const cutoff = now - PETTING_WINDOW_MS;
  while (pettingHistory.length && pettingHistory[0].t < cutoff) {
    pettingHistory.shift();
  }
  if (now < pettingCooldownUntil) return false;

  let reversals = 0;
  let travel = 0;
  let lastSign = 0;
  for (const sample of pettingHistory) {
    travel += Math.abs(sample.dx);
    const sign = Math.sign(sample.dx);
    if (sign !== 0) {
      if (lastSign !== 0 && sign !== lastSign) reversals += 1;
      lastSign = sign;
    }
  }

  if (reversals >= PETTING_MIN_REVERSALS && travel >= PETTING_MIN_TRAVEL_PX) {
    pettingCooldownUntil = now + PETTING_COOLDOWN_MS;
    pettingHistory = [];
    return true;
  }
  return false;
}

function applyHoverAt(x, y) {
  if (dragging) return;
  const el = document.elementFromPoint(x, y);
  const hovering = !!(el && el.closest('#pet'));
  window.petAPI.setIgnoreMouse(!hovering);
  if (hovering !== isHoveringPet) {
    isHoveringPet = hovering;
    // Hovering holds the pet still so it doesn't swim out from under the
    // cursor; the main process folds this into isMovementPaused().
    window.petAPI.setHoverPaused(hovering);
    if (!hovering) pettingHistory = [];
  }
}

window.petAPI.onDirection((dir) => setDirection(dir));
window.petAPI.onSpeech((message) => {
  showBubble(message.text, message.durationMs);
  triggerSpeechAction(message.action);
});
window.petAPI.onAgentState((state) => applyAgentState(state));
window.petAPI.onTaskStatus((state) => renderTaskStatus(state));
window.petAPI.onCharacterPack((pack) => applyCharacterPack(pack));
window.petAPI.onPetLayout((layout) => applyPetLayout(layout));
window.petAPI.onPetConfig((config) => applyPetConfig(config));
window.petAPI.onBump(() => triggerBump());
window.petAPI.onPetAction((action) => triggerPetAction(action));
window.petAPI.getAgentState().then((state) => applyAgentState(state));
window.petAPI.getTaskStatus().then((state) => renderTaskStatus(state));
window.petAPI.getPetConfig().then((config) => applyPetConfig(config));
installCharacterPack()
  .catch((error) => {
    console.error('Failed to install character pack', error);
    showBubble('形象包壞掉了……', 6000);
  });
// The window can move on its own (autonomous swimming, flinging) without the
// cursor ever moving, so mousemove alone isn't enough to keep click-through
// in sync - the main process calls this after every such move with the
// cursor's position in this window's own coordinates.
window.petAPI.onCheckHover((x, y) => applyHoverAt(x, y));

pet.addEventListener('mousedown', (event) => {
  if (event.button !== 0) return;
  dragging = true;
  movedDuringDrag = false;
  dragDistance = 0;
  moveHistory = [];
  event.preventDefault();
});

pet.addEventListener('contextmenu', (event) => {
  event.preventDefault();
  dragging = false;
  movedDuringDrag = false;
  pet.classList.remove('dragging');
  window.petAPI.showContextMenu();
});

pet.addEventListener('click', () => {
  if (movedDuringDrag) return;

  window.petAPI.setPaused(true);
  clearTimeout(bumpTimer);
  pet.classList.remove('hit', 'bump');
  void pet.offsetWidth;
  pet.classList.add('hit');

  window.petAPI.petClicked();

  clearTimeout(hitTimer);
  hitTimer = setTimeout(() => {
    pet.classList.remove('hit');
    window.petAPI.setPaused(false);
  }, 500);
});

document.addEventListener('mousemove', (event) => {
  if (dragging) {
    if (event.movementX !== 0 || event.movementY !== 0) {
      dragDistance += Math.hypot(event.movementX, event.movementY);

      if (!movedDuringDrag) {
        if (dragDistance < DRAG_THRESHOLD_PX) {
          // Still within click tolerance - don't move the window yet.
          return;
        }
        movedDuringDrag = true;
        clearTimeout(hitTimer);
        pet.classList.remove('hit');
        window.petAPI.setPaused(false);
        pet.classList.add('dragging');
        window.petAPI.dragStart();
      }

      window.petAPI.dragMove(event.movementX, event.movementY);

      const now = performance.now();
      moveHistory.push({ t: now, dx: event.movementX, dy: event.movementY });
      const cutoff = now - VELOCITY_WINDOW_MS;
      while (moveHistory.length && moveHistory[0].t < cutoff) {
        moveHistory.shift();
      }
    }
    return;
  }

  applyHoverAt(event.clientX, event.clientY);

  // While the cursor rests on the pet, back-and-forth motion reads as petting:
  // the pet blushes and says something. The blush is a local visual; the line
  // goes through the main process so it uses the phrase engine and language
  // pack like every other bit of speech.
  if (isHoveringPet && event.movementX !== 0 && detectPetting(event.movementX)) {
    triggerBlush();
    window.petAPI.petStroked();
  }
});

document.addEventListener('mouseup', () => {
  if (!dragging) return;
  dragging = false;
  pet.classList.remove('dragging');

  if (movedDuringDrag) {
    const releaseTime = performance.now();
    let velX = 0;
    let velY = 0;

    const lastSample = moveHistory[moveHistory.length - 1];
    const timeSinceLastMove = lastSample ? releaseTime - lastSample.t : Infinity;

    // moveHistory only gets pruned when a new mousemove comes in, so if the
    // hand slowed to a stop before releasing, no new samples arrived to
    // evict the old fast ones - the array would still show a "fast" release
    // even though nothing had moved in a while. STILL_THRESHOLD_MS catches
    // that: a real gap since the last movement means the hand had already
    // settled, so treat it as a deliberate, velocity-free place-down.
    if (timeSinceLastMove < STILL_THRESHOLD_MS) {
      const cutoff = releaseTime - VELOCITY_WINDOW_MS;
      const recent = moveHistory.filter((sample) => sample.t >= cutoff);
      if (recent.length >= 2) {
        const span = Math.max(recent[recent.length - 1].t - recent[0].t, 16);
        const sumDx = recent.reduce((total, sample) => total + sample.dx, 0);
        const sumDy = recent.reduce((total, sample) => total + sample.dy, 0);
        velX = sumDx / span;
        velY = sumDy / span;
      }
    }

    window.petAPI.dragEnd(velX, velY);
  }
});
