// Shared model for wearable accessories (expressions, hats, eyewear, props).
//
// An accessory is authored in its own 100x100 box with an anchor point. Each
// character declares, in its manifest, where that anchor lands on its own art
// and how big the slot is, so one wardrobe fits every character. Nothing is
// written into a character pack: what is worn lives in the config.
//
// Tuning is stored per accessory, not per slot — a straw hat and a beanie each
// remember their own size and position, so swapping between them never makes
// you redo the fit.
(function (root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.accessoryModel = api;
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  // An expression replaces the character's own eyes, so it is picked and left
  // alone rather than nudged around; everything else is tunable.
  const ACCESSORY_SLOTS = Object.freeze([
    Object.freeze({ key: 'face', label: '表情', empty: '原本的', tunable: false }),
    Object.freeze({ key: 'hat', label: '头顶', empty: '不戴', tunable: true }),
    Object.freeze({ key: 'eyewear', label: '眼镜', empty: '不戴', tunable: true }),
    Object.freeze({ key: 'hand', label: '手边', empty: '不拿', tunable: true }),
  ]);

  const ACCESSORY_FIELDS = Object.freeze([
    Object.freeze({ key: 'size', label: '大小', min: 0.4, max: 2, step: 0.01, kind: 'ratio' }),
    Object.freeze({ key: 'width', label: '宽度', min: 0.5, max: 1.8, step: 0.01, kind: 'ratio' }),
    Object.freeze({ key: 'height', label: '高度', min: 0.5, max: 1.8, step: 0.01, kind: 'ratio' }),
    Object.freeze({ key: 'offsetX', label: '左右', min: -30, max: 30, step: 0.5, kind: 'length' }),
    Object.freeze({ key: 'offsetY', label: '上下', min: -30, max: 30, step: 0.5, kind: 'length' }),
  ]);

  const ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

  function defaultTuning() {
    const tuning = {};
    for (const field of ACCESSORY_FIELDS) tuning[field.key] = field.kind === 'ratio' ? 1 : 0;
    return tuning;
  }

  const DEFAULT_TUNING = Object.freeze(defaultTuning());

  function defaultAccessories() {
    const equipped = {};
    for (const slot of ACCESSORY_SLOTS) equipped[slot.key] = null;
    return { equipped, tuning: {} };
  }

  const DEFAULT_ACCESSORIES = Object.freeze(defaultAccessories());

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function quantize(value, step) {
    return Number((Math.round(value / step) * step).toFixed(4));
  }

  function normalizeId(value) {
    return typeof value === 'string' && ID_PATTERN.test(value) ? value : null;
  }

  function normalizeTuning(input) {
    const tuning = defaultTuning();
    if (!input || typeof input !== 'object' || Array.isArray(input)) return tuning;
    for (const field of ACCESSORY_FIELDS) {
      const value = Number(input[field.key]);
      if (!Number.isFinite(value)) continue;
      tuning[field.key] = quantize(clamp(value, field.min, field.max), field.step);
    }
    return tuning;
  }

  function isDefaultTuning(tuning) {
    return ACCESSORY_FIELDS.every((field) => tuning[field.key] === DEFAULT_TUNING[field.key]);
  }

  // Configs written before tuning moved onto the accessory kept the numbers on
  // the slot, next to the id. Fold those onto whatever that slot was wearing.
  function migrateSlotShapedAccessories(input) {
    const spec = defaultAccessories();
    for (const slot of ACCESSORY_SLOTS) {
      const source = input[slot.key];
      if (!source || typeof source !== 'object' || Array.isArray(source)) continue;
      const id = normalizeId(source.id);
      spec.equipped[slot.key] = id;
      if (!id || !slot.tunable) continue;

      const tuning = normalizeTuning(source);
      if (!isDefaultTuning(tuning)) spec.tuning[id] = tuning;
    }
    return spec;
  }

  function normalizeAccessories(input) {
    if (!input || typeof input !== 'object' || Array.isArray(input)) return defaultAccessories();
    if (input.equipped === undefined && input.tuning === undefined) {
      return migrateSlotShapedAccessories(input);
    }

    const spec = defaultAccessories();
    const equipped = input.equipped && typeof input.equipped === 'object' && !Array.isArray(input.equipped)
      ? input.equipped
      : {};
    for (const slot of ACCESSORY_SLOTS) {
      spec.equipped[slot.key] = normalizeId(equipped[slot.key]);
    }

    const tuning = input.tuning && typeof input.tuning === 'object' && !Array.isArray(input.tuning)
      ? input.tuning
      : {};
    for (const key of Object.keys(tuning)) {
      if (!ID_PATTERN.test(key)) continue;
      const normalized = normalizeTuning(tuning[key]);
      // A piece left at its defaults needs no entry: picking it again gives the
      // same result, and the settings file stays small.
      if (!isDefaultTuning(normalized)) spec.tuning[key] = normalized;
    }
    return spec;
  }

  function isEmptyAccessories(spec) {
    const normalized = normalizeAccessories(spec);
    return ACCESSORY_SLOTS.every((slot) => normalized.equipped[slot.key] === null)
      && Object.keys(normalized.tuning).length === 0;
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

  // The tuning a given accessory carries on this character, defaults included.
  function getTuning(spec, accessoryId) {
    return normalizeAccessories(spec).tuning[accessoryId] || defaultTuning();
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

  // `size` scales both axes together; `width` and `height` stretch on top of it.
  function accessoryTransform(slotAnchor, accessoryAnchor, tuning) {
    const base = (Number.isFinite(slotAnchor.scale) ? slotAnchor.scale : 1) * tuning.size;
    const x = slotAnchor.x + tuning.offsetX;
    const y = slotAnchor.y + tuning.offsetY;
    return `translate(${round(x)} ${round(y)}) `
      + `scale(${round(base * tuning.width)} ${round(base * tuning.height)}) `
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
      const id = normalized.equipped[slot.key];
      const slotAnchor = slots[slot.key];
      if (!id || !slotAnchor) continue;

      const accessory = catalog.find((item) => item.id === id && item.slot === slot.key);
      if (!accessory) continue;

      const art = parseAccessoryArt(accessory.svg, svgRoot.ownerDocument);
      if (!art) continue;
      // An expression draws its own eyes, so the character's have to go first.
      if (accessory.hidesEyes) {
        svgRoot.querySelectorAll('.eyes, .eye, .tears, .tear').forEach((node) => node.remove());
      }
      const tuning = slot.tunable ? (normalized.tuning[id] || defaultTuning()) : defaultTuning();
      art.setAttribute('data-accessory-slot', slot.key);
      art.setAttribute('data-accessory-id', id);
      art.setAttribute('class', `accessory accessory-${slot.key}`);
      art.setAttribute('transform', accessoryTransform(slotAnchor, accessory.anchor, tuning));
      svgRoot.appendChild(art);
    }
  }

  return Object.freeze({
    ACCESSORY_FIELDS,
    ACCESSORY_SLOTS,
    DEFAULT_ACCESSORIES,
    DEFAULT_TUNING,
    accessoryTransform,
    applyAccessoriesToSvg,
    defaultAccessories,
    defaultTuning,
    getCharacterSlots,
    getTuning,
    isDefaultTuning,
    isEmptyAccessories,
    normalizeAccessories,
    normalizeAccessoryMap,
    normalizeTuning,
    supportsAccessories,
  });
}));
