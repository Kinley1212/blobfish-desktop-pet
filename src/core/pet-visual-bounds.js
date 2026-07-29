// Converts the composed SVG's local content bounds into the number of pixels
// that can appear above the pet element. Accessories and DIY shapes are
// allowed to extend beyond a character's viewBox, but the native transparent
// window still clips those pixels unless its top boundary accounts for them.
(function (root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.petVisualBounds = api;
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const DEFAULT_EFFECT_RESERVE = 8;

  function requireFinite(value, name) {
    if (!Number.isFinite(value)) throw new TypeError(`${name} must be finite`);
    return value;
  }

  function calculateVisualTopOverflow(viewBox, contentBounds, viewport, effectReserve = DEFAULT_EFFECT_RESERVE) {
    const viewX = requireFinite(viewBox?.x, 'viewBox x');
    const viewY = requireFinite(viewBox?.y, 'viewBox y');
    const viewWidth = requireFinite(viewBox?.width, 'viewBox width');
    const viewHeight = requireFinite(viewBox?.height, 'viewBox height');
    const contentTop = requireFinite(contentBounds?.y, 'content top');
    const viewportWidth = requireFinite(viewport?.width, 'viewport width');
    const viewportHeight = requireFinite(viewport?.height, 'viewport height');
    const layoutTopShift = viewport?.topShift === undefined
      ? 0
      : requireFinite(viewport.topShift, 'layout top shift');
    const reserve = requireFinite(effectReserve, 'effect reserve');

    if (
      viewWidth <= 0
      || viewHeight <= 0
      || viewportWidth <= 0
      || viewportHeight <= 0
      || reserve < 0
    ) {
      throw new RangeError('Pet visual bounds are invalid');
    }

    // Character SVGs use the default xMidYMid meet behavior. The small
    // centering offset matters for packs whose manifest and viewBox aspect
    // ratios differ by a few pixels.
    const scale = Math.min(viewportWidth / viewWidth, viewportHeight / viewHeight);
    const renderedViewHeight = viewHeight * scale;
    const viewportTopPadding = (viewportHeight - renderedViewHeight) / 2;
    const contentTopPx = layoutTopShift
      + viewportTopPadding
      + (contentTop - viewY) * scale;

    // The reserve covers the bundled 5 px upward idle motion, stroke edges,
    // antialiasing, and the upward fringe of the SVG drop shadow.
    return Math.max(0, reserve - contentTopPx);
  }

  return Object.freeze({
    DEFAULT_EFFECT_RESERVE,
    calculateVisualTopOverflow,
  });
}));
