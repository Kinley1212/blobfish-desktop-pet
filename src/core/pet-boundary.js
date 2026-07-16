function calculateVerticalPlacement(desiredPetTop, bounds, metrics) {
  const values = [desiredPetTop, bounds?.minY, bounds?.maxY, metrics?.height, metrics?.topMargin];
  if (values.some((value) => !Number.isFinite(value))) {
    throw new TypeError('Pet boundary values must be finite numbers');
  }
  if (bounds.maxY <= bounds.minY || metrics.height <= 0 || metrics.topMargin < 0) {
    throw new RangeError('Pet boundary dimensions are invalid');
  }

  const minPetTop = bounds.minY;
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
