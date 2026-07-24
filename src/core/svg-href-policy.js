(function exposeSvgHrefPolicy(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.svgHrefPolicy = api;
}(typeof globalThis === 'undefined' ? this : globalThis, () => {
  const MAX_DATA_IMAGE_LENGTH = 700 * 1024;
  const SAFE_DATA_IMAGE = /^data:image\/(?:png|webp);base64,[A-Za-z0-9+/]+={0,2}$/;

  function isSafeSvgHref(value) {
    if (typeof value !== 'string') return false;
    const normalized = value.trim();
    if (normalized.startsWith('#')) return normalized.length > 1;
    return normalized.length <= MAX_DATA_IMAGE_LENGTH && SAFE_DATA_IMAGE.test(normalized);
  }

  return { isSafeSvgHref };
}));
