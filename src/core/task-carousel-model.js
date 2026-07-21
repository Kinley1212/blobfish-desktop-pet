(function exposeTaskCarouselModel(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.taskCarouselModel = api;
}(typeof globalThis === 'object' ? globalThis : this, () => {
  function buildCarouselLayout(items, currentTaskKey, maxVisibleCards = 4) {
    if (!Array.isArray(items) || items.length === 0) {
      return Object.freeze({ frontIndex: -1, frontTaskKey: null, position: 0, total: 0, entries: [] });
    }
    let frontIndex = items.findIndex((item) => item.taskKey === currentTaskKey);
    if (frontIndex < 0) frontIndex = 0;
    const visibleLimit = Math.max(1, Math.floor(maxVisibleCards));
    const entries = items.map((item, index) => {
      const depth = (index - frontIndex + items.length) % items.length;
      return Object.freeze({ item, depth, visible: depth < visibleLimit });
    });
    return Object.freeze({
      frontIndex,
      frontTaskKey: items[frontIndex].taskKey,
      position: frontIndex + 1,
      total: items.length,
      entries: Object.freeze(entries),
    });
  }

  function nextTaskKey(items, currentTaskKey) {
    if (!Array.isArray(items) || items.length === 0) return null;
    const index = items.findIndex((item) => item.taskKey === currentTaskKey);
    return items[(index + 1 + items.length) % items.length].taskKey;
  }

  return Object.freeze({ buildCarouselLayout, nextTaskKey });
}));
