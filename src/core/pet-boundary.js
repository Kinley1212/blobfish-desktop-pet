function calculateVerticalPlacement(desiredPetTop, bounds, metrics) {
  const visualTopOverflow = metrics?.visualTopOverflow === undefined
    ? 0
    : metrics.visualTopOverflow;
  const values = [
    desiredPetTop,
    bounds?.minY,
    bounds?.maxY,
    metrics?.height,
    metrics?.topMargin,
    visualTopOverflow,
  ];
  if (values.some((value) => !Number.isFinite(value))) {
    throw new TypeError('Pet boundary values must be finite numbers');
  }
  if (
    bounds.maxY <= bounds.minY
    || metrics.height <= 0
    || metrics.topMargin < 0
    || visualTopOverflow < 0
    || visualTopOverflow > metrics.topMargin
  ) {
    throw new RangeError('Pet boundary dimensions are invalid');
  }

  // The logical pet box can have visible SVG content above it (for example a
  // tuned hat). Stop that visible content at the work-area edge, while keeping
  // the native BrowserWindow itself inside the same work area.
  const minPetTop = bounds.minY + visualTopOverflow;
  const maxPetTop = Math.max(minPetTop, bounds.maxY - metrics.height);
  const petTop = Math.min(Math.max(desiredPetTop, minPetTop), maxPetTop);
  const windowY = Math.max(bounds.minY, petTop - metrics.topMargin);

  return Object.freeze({
    petTop,
    windowY,
    topOffset: petTop - windowY,
    hitTop: desiredPetTop <= minPetTop,
    hitBottom: desiredPetTop >= maxPetTop,
  });
}

module.exports = { calculateVerticalPlacement };
