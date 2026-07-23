// Shared model for wearable accessories (hats, eyewear, held items).
//
// An accessory is authored in its own 100x100 box with an anchor point. Each
// character declares, in its manifest, where that anchor lands on its own art
// and how big the slot is, so one wardrobe fits every character. Nothing is
// written into a character pack: what is equipped lives in the config.
(function (root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.accessoryModel = api;
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const ACCESSORY_SLOTS = Object.freeze([
    Object.freeze({ key: 'face', label: '表情', empty: '原本的' }),
    Object.freeze({ key: 'hat', label: '头顶', empty: '不戴' }),
    Object.freeze({ key: 'eyewear', label: '眼镜', empty: '不戴' }),
    Object.freeze({ key: 'hand', label: '手边', empty: '不拿' }),
  ]);

  // Same slider vocabulary as the DIY editor, so a slot can be nudged when a
  // shared accessory doesn't quite sit right on a particular character.
  const ACCESSORY_FIELDS = Object.freeze([
    Object.freeze({ key: 'width', label: '宽度', min: 0.4, max: 2, step: 0.01, kind: 'ratio' }),
    Object.freeze({ key: 'height', label: '高度', min: 0.4, max: 2, step: 0.01, kind: 'ratio' }),
    Object.freeze({ key: 'offsetX', label: '左右', min: -30, max: 30, step: 0.5, kind: 'length' }),
    Object.freeze({ key: 'offsetY', label: '上下', min: -30, max: 30, step: 0.5, kind: 'length' }),
  ]);

  const ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

  function defaultSlot() {
    return { id: null, width: 1, height: 1, offsetX: 0, offsetY: 0 };
  }

  function defaultAccessories() {
    const spec = {};
    for (const slot of ACCESSORY_SLOTS) spec[slot.key] = defaultSlot();
    return spec;
  }

  const DEFAULT_ACCESSORIES = Object.freeze(defaultAccessories());

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function quantize(value, step) {
    return Number((Math.round(value / step) * step).toFixed(4));
  }

  function normalizeAccessories(input) {
    const spec = defaultAccessories();
    if (!input || typeof input !== 'object' || Array.isArray(input)) return spec;

    for (const slot of ACCESSORY_SLOTS) {
      const source = input[slot.key];
      if (!source || typeof source !== 'object' || Array.isArray(source)) continue;
      if (typeof source.id === 'string' && ID_PATTERN.test(source.id)) spec[slot.key].id = source.id;
      for (const field of ACCESSORY_FIELDS) {
        // Configs written while width and height were one uniform `size`
        // slider still load: the old value seeds both axes.
        const raw = source[field.key] === undefined && (field.key === 'width' || field.key === 'height')
          ? source.size
          : source[field.key];
        const value = Number(raw);
        if (!Number.isFinite(value)) continue;
        spec[slot.key][field.key] = quantize(clamp(value, field.min, field.max), field.step);
      }
    }
    return spec;
  }

  // A slot with nothing equipped carries no meaning, so a spec counts as empty
  // once every slot is bare - whatever the sliders were left at.
  function isEmptyAccessories(spec) {
    const normalized = normalizeAccessories(spec);
    return ACCESSORY_SLOTS.every((slot) => normalized[slot.key].id === null);
  }

  function normalizeAccessoryMap(input) {
    const map = {};
    if (!input || typeof input !== 'object' || Array.isArray(input)) return map;
    for (const key of Object.keys(input)) {
      if (!ID_PATTERN.test(key)) continue;
      const spec = normalizeAccessories(input[key]);
      if (!isEmptyAccessories(spec)) map[key] = spec;
    }
    return map;
  }

  function getCharacterSlots(manifest) {
    const slots = manifest && manifest.accessories && manifest.accessories.slots;
    return slots && typeof slots === 'object' ? slots : null;
  }

  function supportsAccessories(manifest) {
    const slots = getCharacterSlots(manifest);
    return Boolean(slots && ACCESSORY_SLOTS.some((slot) => slots[slot.key]));
  }

  function round(value) {
    return Number(value.toFixed(3));
  }

  // Maps the accessory's anchor onto the character's slot, then applies the
  // character's slot scale and the user's own nudges.
  function accessoryTransform(slotAnchor, accessoryAnchor, settings) {
    const base = Number.isFinite(slotAnchor.scale) ? slotAnchor.scale : 1;
    const x = slotAnchor.x + settings.offsetX;
    const y = slotAnchor.y + settings.offsetY;
    return `translate(${round(x)} ${round(y)}) `
      + `scale(${round(base * settings.width)} ${round(base * settings.height)}) `
      + `translate(${round(-accessoryAnchor.x)} ${round(-accessoryAnchor.y)})`;
  }

  // --- DOM side -----------------------------------------------------------

  function parseAccessoryArt(svgText, ownerDocument) {
    const parsed = new DOMParser().parseFromString(svgText, 'image/svg+xml');
    if (parsed.querySelector('parsererror')) return null;
    parsed.querySelectorAll('script, foreignObject, iframe, object, embed').forEach((node) => node.remove());

    const namespace = 'http://www.w3.org/2000/svg';
    const group = ownerDocument.createElementNS(namespace, 'g');
    for (const child of [...parsed.documentElement.childNodes]) {
      group.appendChild(ownerDocument.importNode(child, true));
    }
    return group;
  }

  // Accessories are drawn last so they sit on top of the character, and are
  // rebuilt from scratch each time rather than patched in place.
  function applyAccessoriesToSvg(svgRoot, manifest, catalog, spec) {
    if (!svgRoot) return;
    svgRoot.querySelectorAll('[data-accessory-slot]').forEach((node) => node.remove());

    const slots = getCharacterSlots(manifest);
    if (!slots || !Array.isArray(catalog)) return;
    const normalized = normalizeAccessories(spec);

    for (const slot of ACCESSORY_SLOTS) {
      const settings = normalized[slot.key];
      const slotAnchor = slots[slot.key];
      if (!settings.id || !slotAnchor) continue;

      const accessory = catalog.find((item) => item.id === settings.id && item.slot === slot.key);
      if (!accessory) continue;

      const art = parseAccessoryArt(accessory.svg, svgRoot.ownerDocument);
      if (!art) continue;
      // An expression draws its own eyes, so the character's have to go first.
      if (accessory.hidesEyes) {
        svgRoot.querySelectorAll('.eyes, .eye, .tears, .tear').forEach((node) => node.remove());
      }
      art.setAttribute('data-accessory-slot', slot.key);
      art.setAttribute('class', `accessory accessory-${slot.key}`);
      art.setAttribute('transform', accessoryTransform(slotAnchor, accessory.anchor, settings));
      svgRoot.appendChild(art);
    }
  }

  return Object.freeze({
    ACCESSORY_FIELDS,
    ACCESSORY_SLOTS,
    DEFAULT_ACCESSORIES,
    accessoryTransform,
    applyAccessoriesToSvg,
    defaultAccessories,
    getCharacterSlots,
    isEmptyAccessories,
    normalizeAccessories,
    normalizeAccessoryMap,
    supportsAccessories,
  });
}));
