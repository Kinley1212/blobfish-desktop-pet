const pet = document.getElementById('pet');
const bubble = document.getElementById('bubble');

const VELOCITY_WINDOW_MS = 300;
const BLINK_MIN_MS = 3500;
const BLINK_MAX_MS = 9000;
const BLINK_DURATION_MS = 180;
const DOUBLE_BLINK_CHANCE = 0.12;
// Minimum cumulative pointer movement (px) before a press-and-move counts as
// a drag. Below this it's treated as a click even if the hand wasn't
// perfectly still between mousedown and mouseup.
const DRAG_THRESHOLD_PX = 4;
// If the pointer hasn't moved for at least this long before release, the
// hand had already come to a stop - treat the release as velocity-free.
const STILL_THRESHOLD_MS = 60;

let bubbleTimer = null;
let hitTimer = null;
let bumpTimer = null;
let dragging = false;
let movedDuringDrag = false;
let dragDistance = 0;
let moveHistory = []; // recent { t, dx, dy } samples, used to estimate release velocity
let blinkTimer = null;
let speechActionTimer = null;
let characterManifest = null;
let petScale = 1;

function applyPetConfig(config = {}) {
  const nextScale = Number(config.scale);
  petScale = Number.isFinite(nextScale) ? Math.min(1.5, Math.max(0.65, nextScale)) : 1;
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

function applyHoverAt(x, y) {
  if (dragging) return;
  const el = document.elementFromPoint(x, y);
  const hovering = !!(el && el.closest('#pet'));
  window.petAPI.setIgnoreMouse(!hovering);
}

window.petAPI.onDirection((dir) => setDirection(dir));
window.petAPI.onSpeech((message) => {
  showBubble(message.text, message.durationMs);
  triggerSpeechAction(message.action);
});
window.petAPI.onAgentState((state) => applyAgentState(state));
window.petAPI.onCharacterPack((pack) => applyCharacterPack(pack));
window.petAPI.onPetConfig((config) => applyPetConfig(config));
window.petAPI.onBump(() => triggerBump());
window.petAPI.onPetAction((action) => triggerPetAction(action));
window.petAPI.getAgentState().then((state) => applyAgentState(state));
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
