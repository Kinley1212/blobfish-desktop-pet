const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const fs = require('node:fs');
const path = require('node:path');
const {
  bindGracefulWindowClose,
  isLiveWindow,
} = require('../src/core/window-lifecycle');

test('a standard pet-window close is redirected through graceful quit', () => {
  const window = new EventEmitter();
  let quitRequests = 0;
  let prevented = false;
  bindGracefulWindowClose(window, {
    canCloseImmediately: () => false,
    requestQuit: () => {
      quitRequests += 1;
    },
  });

  window.emit('close', {
    preventDefault() {
      prevented = true;
    },
  });

  assert.equal(prevented, true);
  assert.equal(quitRequests, 1);
});

test('the final app quit is allowed to close the pet window', () => {
  const window = new EventEmitter();
  let quitRequests = 0;
  let prevented = false;
  bindGracefulWindowClose(window, {
    canCloseImmediately: () => true,
    requestQuit: () => {
      quitRequests += 1;
    },
  });

  window.emit('close', {
    preventDefault() {
      prevented = true;
    },
  });

  assert.equal(prevented, false);
  assert.equal(quitRequests, 0);
});

test('closed cleanup runs even when no close event was observed first', () => {
  const window = new EventEmitter();
  let cleaned = false;
  bindGracefulWindowClose(window, {
    canCloseImmediately: () => false,
    requestQuit: () => {},
    onClosed: () => {
      cleaned = true;
    },
  });

  window.emit('closed');

  assert.equal(cleaned, true);
});

test('only a non-destroyed BrowserWindow-like object is live', () => {
  assert.equal(isLiveWindow(null), false);
  assert.equal(isLiveWindow({}), false);
  assert.equal(isLiveWindow({ isDestroyed: () => true }), false);
  assert.equal(isLiveWindow({ isDestroyed: () => false }), true);
});

test('the main pet window cannot be minimized and owns its motion timer cleanup', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'src', 'main.js'), 'utf8');
  const windowStart = source.indexOf('win = new BrowserWindow({');
  const windowEnd = source.indexOf('\n  });', windowStart);
  const windowOptions = source.slice(windowStart, windowEnd);

  assert.ok(windowStart >= 0 && windowEnd > windowStart);
  assert.match(windowOptions, /minimizable:\s*false/);
  assert.match(source, /bindGracefulWindowClose\(petWindow,/);
  assert.match(source, /movementIntervalId = setTimeout\(runMovementTick, delayMs\)/);
  assert.match(source, /isMovementPaused\(\) \|\| flingIntervalId \? 500 : TICK_MS/);
  assert.match(source, /function stopPetMotionTimers\(\)/);
  assert.match(source, /clearTimeout\(movementIntervalId\)/);
  assert.match(source, /if \(win === petWindow\) win = null/);
  assert.match(source, /!isLiveWindow\(win\)/);
});
