function roundWindowCoordinate(value) {
  if (!Number.isFinite(value)) throw new TypeError('Window coordinate must be finite');
  return Math.round(value) || 0;
}

function advanceFractionalCoordinate(preciseValue, nativeValue, delta) {
  if (!Number.isFinite(nativeValue) || !Number.isFinite(delta)) {
    throw new TypeError('Window movement values must be finite');
  }

  const base = Number.isFinite(preciseValue)
    && roundWindowCoordinate(preciseValue) === nativeValue
    ? preciseValue
    : nativeValue;
  return base + delta;
}

module.exports = { advanceFractionalCoordinate, roundWindowCoordinate };
