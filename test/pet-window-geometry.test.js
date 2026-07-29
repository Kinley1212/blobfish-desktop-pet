const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const {
  BUBBLE_STACK_RESERVE,
  PET_BOTTOM_MARGIN,
  PET_SCALE_MAX,
  PET_SCALE_MIN,
  PET_WINDOW_HEIGHT,
  PET_WINDOW_WIDTH,
  calculatePetMetrics,
  calculatePetRecoveryPlacement,
  calculateVerticalRoamPlacement,
  getMaxPetScale,
} = require('../src/core/pet-window-geometry');

test('renderer viewport stays in sync with the native pet window', () => {
  const css = fs.readFileSync(path.join(__dirname, '../src/styles/app.css'), 'utf8');
  assert.match(css, new RegExp(`--pet-window-width:\\s*${PET_WINDOW_WIDTH}px`));
  assert.match(css, new RegExp(`--pet-window-height:\\s*${PET_WINDOW_HEIGHT}px`));
  assert.match(css, new RegExp(`--pet-bottom-margin:\\s*${PET_BOTTOM_MARGIN}px`));
  assert.match(
    css,
    /--pet-top:\s*calc\(var\(--pet-window-height\) - var\(--pet-bottom-margin\) - var\(--pet-height\)\)/,
  );
  assert.equal(css.match(/--pet-top\s*:/g)?.length, 1, 'CSS must define one initial pet-top source');
  assert.doesNotMatch(css, /var\(--pet-top,/, 'pet and bubbles must not carry stale local fallbacks');
});

test('the largest bundled pet keeps stacked task and speech bubbles inside the window', () => {
  const metrics = calculatePetMetrics(
    { width: 118, height: 98 },
    1.5,
    { width: PET_WINDOW_WIDTH, height: PET_WINDOW_HEIGHT, bottomMargin: PET_BOTTOM_MARGIN },
  );

  assert.equal(metrics.width, 177);
  assert.equal(metrics.height, 147);
  assert.ok(metrics.topMargin >= BUBBLE_STACK_RESERVE);
  assert.ok(
    BUBBLE_STACK_RESERVE + metrics.height + BUBBLE_STACK_RESERVE <= PET_WINDOW_HEIGHT,
    'the placement switch must have enough room for the stacked bubbles on either side',
  );
});

test('the character-pack contract rejects art that cannot leave room for bubbles', () => {
  const geometry = {
    width: PET_WINDOW_WIDTH,
    height: PET_WINDOW_HEIGHT,
    bottomMargin: PET_BOTTOM_MARGIN,
  };

  assert.throws(
    () => calculatePetMetrics({ width: 512, height: 512 }, PET_SCALE_MAX, geometry),
    /window width/,
  );
  assert.throws(
    () => calculatePetMetrics({ width: 512, height: 512 }, PET_SCALE_MIN, geometry),
    /bubble/,
  );
  assert.throws(
    () => getMaxPetScale({ width: 512, height: 512 }, geometry),
    /minimum scale/,
  );
});

test('every bundled character supports the full configured scale range with bubbles', () => {
  const charactersRoot = path.join(__dirname, '../src/packs/characters');
  const geometry = {
    width: PET_WINDOW_WIDTH,
    height: PET_WINDOW_HEIGHT,
    bottomMargin: PET_BOTTOM_MARGIN,
  };

  for (const folder of fs.readdirSync(charactersRoot)) {
    const manifestPath = path.join(charactersRoot, folder, 'manifest.json');
    if (!fs.existsSync(manifestPath)) continue;
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    assert.doesNotThrow(
      () => calculatePetMetrics(manifest.size, PET_SCALE_MIN, geometry),
      `${manifest.id} must fit at minimum scale`,
    );
    assert.doesNotThrow(
      () => calculatePetMetrics(manifest.size, PET_SCALE_MAX, geometry),
      `${manifest.id} must fit at maximum scale`,
    );
    assert.equal(getMaxPetScale(manifest.size, geometry), PET_SCALE_MAX);
  }
});

test('pet metrics reject horizontal overflow independently of height', () => {
  assert.throws(
    () => calculatePetMetrics(
      { width: 512, height: 32 },
      0.7,
      { width: PET_WINDOW_WIDTH, height: PET_WINDOW_HEIGHT, bottomMargin: PET_BOTTOM_MARGIN },
    ),
    /window width/,
  );
});

test('pet metrics reject vertical overflow independently of width', () => {
  assert.throws(
    () => calculatePetMetrics(
      { width: 32, height: 512 },
      0.8,
      { width: PET_WINDOW_WIDTH, height: PET_WINDOW_HEIGHT, bottomMargin: PET_BOTTOM_MARGIN },
    ),
    /window height/,
  );
});

test('a taller transparent window preserves the pet feet at the bottom of the work area', () => {
  const workAreaBottom = 925;
  const metrics = calculatePetMetrics(
    { width: 118, height: 98 },
    1.5,
    { width: PET_WINDOW_WIDTH, height: PET_WINDOW_HEIGHT, bottomMargin: PET_BOTTOM_MARGIN },
  );
  const windowY = workAreaBottom - PET_WINDOW_HEIGHT;
  const petBottom = windowY + metrics.topMargin + metrics.height;

  assert.equal(petBottom, workAreaBottom - PET_BOTTOM_MARGIN);
});

test('vertical roaming releases the native window soon after bouncing off the screen top', () => {
  const metrics = {
    width: 120,
    height: 90,
    offsetX: 110,
    topMargin: 300,
  };
  const bounds = { minY: 25, maxY: 900 };

  assert.deepEqual(calculateVerticalRoamPlacement(25, bounds, metrics), {
    petTop: 25,
    windowY: 25,
    topOffset: 0,
    hitTop: true,
    hitBottom: false,
  });
  assert.deepEqual(calculateVerticalRoamPlacement(151, bounds, metrics), {
    petTop: 151,
    windowY: 25,
    topOffset: BUBBLE_STACK_RESERVE,
    hitTop: false,
    hitBottom: false,
  });
  assert.deepEqual(calculateVerticalRoamPlacement(200, bounds, metrics), {
    petTop: 200,
    windowY: 74,
    topOffset: BUBBLE_STACK_RESERVE,
    hitTop: false,
    hitBottom: false,
  });
});

test('display recovery keeps an already visible pet on its current display', () => {
  const metrics = {
    width: 120,
    height: 90,
    offsetX: 110,
    topMargin: 300,
  };
  const placement = calculatePetRecoveryPlacement(
    { x: 500, y: 300, petTopOffset: 280 },
    metrics,
    [{ x: 0, y: 25, width: 1440, height: 875 }],
  );

  assert.deepEqual(placement, {
    windowX: 500,
    windowY: 300,
    topOffset: 280,
    petLeft: 610,
    petTop: 580,
    displayIndex: 0,
  });
});

test('display recovery moves an orphaned pet to the nearest available work area', () => {
  const metrics = {
    width: 120,
    height: 90,
    offsetX: 110,
    topMargin: 300,
  };
  const placement = calculatePetRecoveryPlacement(
    { x: 1800, y: 400, petTopOffset: 260 },
    metrics,
    [
      { x: 0, y: 25, width: 1440, height: 875 },
      { x: -1280, y: 0, width: 1280, height: 800 },
    ],
  );

  assert.deepEqual(placement, {
    windowX: 1210,
    windowY: 400,
    topOffset: 260,
    petLeft: 1320,
    petTop: 660,
    displayIndex: 0,
  });
});

test('display recovery preserves a pet already visible on a non-primary display', () => {
  const metrics = { width: 120, height: 90, offsetX: 110, topMargin: 300 };
  const placement = calculatePetRecoveryPlacement(
    { x: 1600, y: -150, petTopOffset: 100 },
    metrics,
    [
      { x: 0, y: 25, width: 1440, height: 875 },
      { x: 1440, y: -200, width: 1920, height: 1080 },
    ],
  );

  assert.deepEqual(placement, {
    windowX: 1600,
    windowY: -150,
    topOffset: 100,
    petLeft: 1710,
    petTop: -50,
    displayIndex: 1,
  });
});

test('display recovery chooses a real work area instead of a bounding-box gap', () => {
  const metrics = { width: 120, height: 90, offsetX: 110, topMargin: 300 };
  const placement = calculatePetRecoveryPlacement(
    { x: -220, y: 300, petTopOffset: 280 },
    metrics,
    [
      { x: -1600, y: 25, width: 1200, height: 875 },
      { x: 0, y: 25, width: 1440, height: 875 },
    ],
  );

  assert.deepEqual(placement, {
    windowX: -110,
    windowY: 300,
    topOffset: 280,
    petLeft: 0,
    petTop: 580,
    displayIndex: 1,
  });
});

test('gap recovery also normalizes a native window top above its target work area', () => {
  const metrics = { width: 120, height: 90, offsetX: 110, topMargin: 300 };
  const placement = calculatePetRecoveryPlacement(
    { x: -220, y: -75, petTopOffset: 300 },
    metrics,
    [
      { x: -1600, y: 25, width: 1200, height: 875 },
      { x: 0, y: 25, width: 1440, height: 875 },
    ],
  );

  assert.deepEqual(placement, {
    windowX: -110,
    windowY: 25,
    topOffset: 200,
    petLeft: 0,
    petTop: 225,
    displayIndex: 1,
  });
});

test('motion can cross touching displays while the whole pet remains visible', () => {
  const metrics = { width: 120, height: 90, offsetX: 110, topMargin: 300 };
  const placement = calculatePetRecoveryPlacement(
    { x: 830, y: 300, petTopOffset: 280 },
    metrics,
    [
      { x: 0, y: 25, width: 1000, height: 875 },
      { x: 1000, y: 25, width: 1200, height: 875 },
    ],
  );

  assert.deepEqual(placement, {
    windowX: 830,
    windowY: 300,
    topOffset: 280,
    petLeft: 940,
    petTop: 580,
    displayIndex: 0,
  });
});

test('motion can cross vertically touching displays while the whole pet remains visible', () => {
  const metrics = { width: 120, height: 90, offsetX: 110, topMargin: 300 };
  const workAreas = [
    { x: 0, y: 0, width: 1000, height: 500 },
    { x: 0, y: 500, width: 1000, height: 700 },
  ];
  const upperPlacement = calculatePetRecoveryPlacement(
    { x: 300, y: 170, petTopOffset: 280 },
    metrics,
    workAreas,
  );

  assert.deepEqual(upperPlacement, {
    windowX: 300,
    windowY: 170,
    topOffset: 280,
    petLeft: 410,
    petTop: 450,
    displayIndex: 0,
  });

  const lowerPlacement = calculatePetRecoveryPlacement(
    { x: 300, y: 230, petTopOffset: 280 },
    metrics,
    workAreas,
  );
  assert.deepEqual(lowerPlacement, {
    windowX: 300,
    windowY: 500,
    topOffset: 10,
    petLeft: 410,
    petTop: 510,
    displayIndex: 1,
  });
});

test('a visible pet normalizes an unreachable native window top without moving the sprite', () => {
  const metrics = { width: 120, height: 90, offsetX: 110, topMargin: 300 };
  const placement = calculatePetRecoveryPlacement(
    { x: 300, y: -75, petTopOffset: 300 },
    metrics,
    [{ x: 0, y: 25, width: 1000, height: 700 }],
  );

  assert.deepEqual(placement, {
    windowX: 300,
    windowY: 25,
    topOffset: 200,
    petLeft: 410,
    petTop: 225,
    displayIndex: 0,
  });
});

test('motion can cross vertically offset displays only through their visible overlap', () => {
  const metrics = { width: 120, height: 90, offsetX: 110, topMargin: 300 };
  const workAreas = [
    { x: 0, y: 25, width: 1000, height: 875 },
    { x: 1000, y: 400, width: 1200, height: 600 },
  ];

  const overlapPlacement = calculatePetRecoveryPlacement(
    { x: 830, y: 300, petTopOffset: 280 },
    metrics,
    workAreas,
  );
  assert.equal(overlapPlacement.windowX, 830);
  assert.equal(overlapPlacement.petLeft, 940);
  assert.equal(overlapPlacement.petTop, 580);

  const holePlacement = calculatePetRecoveryPlacement(
    { x: 830, y: -150, petTopOffset: 280 },
    metrics,
    workAreas,
  );
  assert.equal(holePlacement.windowX, 770);
  assert.equal(holePlacement.petLeft, 880);
  assert.equal(holePlacement.petTop, 130);
  assert.equal(holePlacement.displayIndex, 0);
});

test('display recovery respects changed menu-bar and Dock work-area edges', () => {
  const metrics = {
    width: 120,
    height: 90,
    offsetX: 110,
    topMargin: 300,
  };
  const placement = calculatePetRecoveryPlacement(
    { x: -150, y: -80, petTopOffset: 0 },
    metrics,
    [{ x: 0, y: 30, width: 1000, height: 700 }],
  );

  assert.deepEqual(placement, {
    windowX: -110,
    windowY: 30,
    topOffset: 0,
    petLeft: 0,
    petTop: 30,
    displayIndex: 0,
  });

  const dockPlacement = calculatePetRecoveryPlacement(
    { x: 500, y: 700, petTopOffset: 260 },
    metrics,
    [{ x: 0, y: 30, width: 1000, height: 700 }],
  );
  assert.deepEqual(dockPlacement, {
    windowX: 500,
    windowY: 340,
    topOffset: 300,
    petLeft: 610,
    petTop: 640,
    displayIndex: 0,
  });
});

test('display recovery rejects empty or malformed geometry', () => {
  const metrics = { width: 120, height: 90, offsetX: 110, topMargin: 300 };
  assert.throws(
    () => calculatePetRecoveryPlacement({ x: 0, y: 0, petTopOffset: 0 }, metrics, []),
    /work area/,
  );
  assert.throws(
    () => calculatePetRecoveryPlacement(
      { x: 0, y: 0, petTopOffset: 0 },
      metrics,
      [{ x: 0, y: 0, width: Number.NaN, height: 700 }],
    ),
    /work area/,
  );
});

test('drag, automatic movement, and fling project against real work areas', () => {
  const mainSource = fs.readFileSync(path.join(__dirname, '../src/main.js'), 'utf8');
  assert.doesNotMatch(
    mainSource,
    /getCombinedBounds/,
    'no motion or resize path may treat the exterior multi-display bounding box as visible',
  );

  const configStart = mainSource.indexOf('function applyConfig(');
  const configEnd = mainSource.indexOf('\nfunction persistConfig', configStart);
  assert.ok(configStart >= 0 && configEnd > configStart);
  assert.match(
    mainSource.slice(configStart, configEnd),
    /projectPetWindowPosition\(/,
    'character and scale changes must also recover into a real work area',
  );

  const dragStart = mainSource.indexOf("ipcMain.on('drag-move'");
  const dragEnd = mainSource.indexOf("ipcMain.on('drag-end'", dragStart);
  assert.ok(dragStart >= 0 && dragEnd > dragStart);
  const dragSource = mainSource.slice(dragStart, dragEnd);
  assert.match(dragSource, /projectPetWindowPosition\(/);
  assert.doesNotMatch(dragSource, /getCombinedBounds\(/);

  const movementStart = mainSource.indexOf('setInterval(() => {', dragEnd);
  const movementEnd = mainSource.indexOf("win.webContents.once('did-finish-load'", movementStart);
  assert.ok(movementStart >= 0 && movementEnd > movementStart);
  const movementSource = mainSource.slice(movementStart, movementEnd);
  assert.match(movementSource, /projectPetWindowPosition\(/);
  assert.doesNotMatch(movementSource, /getCombinedBounds\(/);

  const flingStart = mainSource.indexOf('function startFling(');
  const flingEnd = mainSource.indexOf('\nfunction scheduleReminders', flingStart);
  assert.ok(flingStart >= 0 && flingEnd > flingStart);
  const flingSource = mainSource.slice(flingStart, flingEnd);
  assert.match(flingSource, /projectPetWindowPosition\(/);
  assert.doesNotMatch(flingSource, /getCombinedBounds\(/);
});
