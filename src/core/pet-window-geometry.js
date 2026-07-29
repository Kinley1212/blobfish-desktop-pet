const { calculateVerticalPlacement } = require('./pet-boundary');

const PET_WINDOW_WIDTH = 340;
const PET_WINDOW_HEIGHT = 400;
const PET_BOTTOM_MARGIN = 10;
const PET_SCALE_MIN = 0.65;
const PET_SCALE_MAX = 1.5;
const PET_SCALE_STEP = 0.05;

// The task carousel occupies 58 px. When speech is present at the same time,
// CSS moves it another 62 px away from the pet; the longest bundled line is
// three rows tall. 126 px therefore leaves a small safety margin on either
// side of the largest built-in pet.
const BUBBLE_STACK_RESERVE = 126;

function requireFinite(value, name) {
  if (!Number.isFinite(value)) throw new TypeError(`${name} must be finite`);
  return value;
}

function isValidWorkArea(area) {
  return Boolean(
    area
    && Number.isFinite(area.x)
    && Number.isFinite(area.y)
    && Number.isFinite(area.width)
    && Number.isFinite(area.height)
    && area.width > 0
    && area.height > 0,
  );
}

function calculatePetMetrics(size, scale, windowGeometry = {}) {
  const sourceWidth = requireFinite(size?.width, 'pet width');
  const sourceHeight = requireFinite(size?.height, 'pet height');
  const safeScale = requireFinite(scale, 'pet scale');
  const windowWidth = requireFinite(windowGeometry.width, 'window width');
  const windowHeight = requireFinite(windowGeometry.height, 'window height');
  const bottomMargin = requireFinite(windowGeometry.bottomMargin, 'pet bottom margin');
  const width = sourceWidth * safeScale;
  const height = sourceHeight * safeScale;

  if (sourceWidth <= 0 || sourceHeight <= 0 || safeScale <= 0) {
    throw new RangeError('Pet dimensions and scale must be positive');
  }
  if (windowWidth <= 0 || windowHeight <= 0 || bottomMargin < 0) {
    throw new RangeError('Pet window geometry is invalid');
  }
  if (width > windowWidth) throw new RangeError('Pet exceeds the available window width');
  if (height + BUBBLE_STACK_RESERVE * 2 > windowHeight) {
    throw new RangeError('Pet exceeds the available window height reserved for bubbles');
  }

  return Object.freeze({
    width,
    height,
    offsetX: (windowWidth - width) / 2,
    topMargin: windowHeight - bottomMargin - height,
  });
}

function getMaxPetScale(size, windowGeometry = {}, options = {}) {
  const sourceWidth = requireFinite(size?.width, 'pet width');
  const sourceHeight = requireFinite(size?.height, 'pet height');
  const windowWidth = requireFinite(windowGeometry.width, 'window width');
  const windowHeight = requireFinite(windowGeometry.height, 'window height');
  const bottomMargin = requireFinite(windowGeometry.bottomMargin, 'pet bottom margin');
  const minScale = options.minScale === undefined
    ? PET_SCALE_MIN
    : requireFinite(options.minScale, 'minimum pet scale');
  const maxScale = options.maxScale === undefined
    ? PET_SCALE_MAX
    : requireFinite(options.maxScale, 'maximum pet scale');
  const step = options.step === undefined
    ? PET_SCALE_STEP
    : requireFinite(options.step, 'pet scale step');

  if (
    sourceWidth <= 0
    || sourceHeight <= 0
    || windowWidth <= 0
    || windowHeight <= 0
    || bottomMargin < 0
    || minScale <= 0
    || maxScale < minScale
    || step <= 0
  ) {
    throw new RangeError('Pet scale geometry is invalid');
  }

  const exactLimit = Math.min(
    maxScale,
    windowWidth / sourceWidth,
    (windowHeight - BUBBLE_STACK_RESERVE * 2) / sourceHeight,
  );
  if (exactLimit + Number.EPSILON < minScale) {
    throw new RangeError('Character cannot fit inside the pet window at the minimum scale');
  }

  const stepCount = Math.floor(((exactLimit - minScale) / step) + 1e-9);
  return Number(Math.min(maxScale, minScale + stepCount * step).toFixed(10));
}

function squaredDistanceToRect(point, rect) {
  const right = rect.x + rect.width;
  const bottom = rect.y + rect.height;
  const dx = point.x < rect.x ? rect.x - point.x : (point.x > right ? point.x - right : 0);
  const dy = point.y < rect.y ? rect.y - point.y : (point.y > bottom ? point.y - bottom : 0);
  return dx * dx + dy * dy;
}

function isRectCoveredByWorkAreas(rect, workAreas) {
  const right = rect.x + rect.width;
  const bottom = rect.y + rect.height;
  const intersections = workAreas
    .map((area) => ({
      x: Math.max(rect.x, area.x),
      y: Math.max(rect.y, area.y),
      right: Math.min(right, area.x + area.width),
      bottom: Math.min(bottom, area.y + area.height),
    }))
    .filter((area) => area.right > area.x && area.bottom > area.y);
  if (intersections.length === 0) return false;

  const xBoundaries = [...new Set([
    rect.x,
    right,
    ...intersections.flatMap((area) => [area.x, area.right]),
  ])].sort((a, b) => a - b);
  const epsilon = 1e-9;

  for (let index = 0; index < xBoundaries.length - 1; index += 1) {
    const startX = xBoundaries[index];
    const endX = xBoundaries[index + 1];
    if (endX - startX <= epsilon) continue;
    const probeX = (startX + endX) / 2;
    const verticalIntervals = intersections
      .filter((area) => area.x <= probeX && area.right >= probeX)
      .map((area) => [area.y, area.bottom])
      .sort((left, rightInterval) => left[0] - rightInterval[0]);

    let coveredUntil = rect.y;
    for (const [startY, endY] of verticalIntervals) {
      if (startY > coveredUntil + epsilon) break;
      coveredUntil = Math.max(coveredUntil, endY);
      if (coveredUntil >= bottom - epsilon) break;
    }
    if (coveredUntil < bottom - epsilon) return false;
  }
  return true;
}

function calculatePetRecoveryPlacement(windowPosition, metrics, workAreas) {
  const windowX = requireFinite(windowPosition?.x, 'window x');
  const windowY = requireFinite(windowPosition?.y, 'window y');
  const petTopOffset = requireFinite(windowPosition?.petTopOffset, 'pet top offset');
  const width = requireFinite(metrics?.width, 'pet width');
  const height = requireFinite(metrics?.height, 'pet height');
  const offsetX = requireFinite(metrics?.offsetX, 'pet horizontal offset');
  const topMargin = requireFinite(metrics?.topMargin, 'pet top margin');

  if (width <= 0 || height <= 0 || topMargin < 0) {
    throw new RangeError('Pet recovery metrics are invalid');
  }
  if (!Array.isArray(workAreas) || workAreas.length === 0 || workAreas.some((area) => !isValidWorkArea(area))) {
    throw new RangeError('Pet recovery requires a valid work area');
  }

  const originalPetLeft = windowX + offsetX;
  const originalPetTop = windowY + petTopOffset;
  const petCenter = {
    x: originalPetLeft + width / 2,
    y: originalPetTop + height / 2,
  };

  let displayIndex = 0;
  let nearestDistance = squaredDistanceToRect(petCenter, workAreas[0]);
  for (let index = 1; index < workAreas.length; index += 1) {
    const distance = squaredDistanceToRect(petCenter, workAreas[index]);
    if (distance < nearestDistance) {
      displayIndex = index;
      nearestDistance = distance;
    }
  }

  if (
    petTopOffset >= 0
    && petTopOffset <= topMargin
    && isRectCoveredByWorkAreas(
      { x: originalPetLeft, y: originalPetTop, width, height },
      workAreas,
    )
  ) {
    // Keep the absolute sprite position, but make the much taller transparent
    // BrowserWindow reachable. macOS silently clamps a native window whose
    // top is above the workArea carrying the sprite, otherwise our tracked
    // top offset diverges from what is actually on screen. Anchoring at the
    // sprite's top-centre also lets it cross a genuine vertical display seam:
    // the anchor changes screens only when the sprite top does.
    const anchor = workAreas.find((area) => (
      petCenter.x >= area.x
      && petCenter.x < area.x + area.width
      && originalPetTop >= area.y
      && originalPetTop < area.y + area.height
    )) || workAreas[displayIndex];
    const reachableWindowY = Math.max(anchor.y, windowY);
    return Object.freeze({
      windowX,
      windowY: reachableWindowY,
      topOffset: originalPetTop - reachableWindowY,
      petLeft: originalPetLeft,
      petTop: originalPetTop,
      displayIndex,
    });
  }

  const target = workAreas[displayIndex];
  const maxPetLeft = Math.max(target.x, target.x + target.width - width);
  const maxPetTop = Math.max(target.y, target.y + target.height - height);
  const petLeft = Math.min(Math.max(originalPetLeft, target.x), maxPetLeft);
  const desiredPetTop = Math.min(Math.max(originalPetTop, target.y), maxPetTop);
  const canKeepVerticalWindow = desiredPetTop === originalPetTop
    && petTopOffset >= 0
    && petTopOffset <= topMargin
    && windowY >= target.y;
  const vertical = canKeepVerticalWindow
    ? { windowY, topOffset: petTopOffset, petTop: originalPetTop }
    : calculateVerticalPlacement(
      desiredPetTop,
      { minY: target.y, maxY: target.y + target.height },
      { height, topMargin },
    );

  return Object.freeze({
    windowX: petLeft - offsetX,
    windowY: vertical.windowY,
    topOffset: vertical.topOffset,
    petLeft,
    petTop: vertical.petTop,
    displayIndex,
  });
}

module.exports = {
  BUBBLE_STACK_RESERVE,
  PET_BOTTOM_MARGIN,
  PET_SCALE_MAX,
  PET_SCALE_MIN,
  PET_SCALE_STEP,
  PET_WINDOW_HEIGHT,
  PET_WINDOW_WIDTH,
  calculatePetMetrics,
  calculatePetRecoveryPlacement,
  getMaxPetScale,
};
