// Shared model for the "捏鱼" (DIY) appearance editor.
//
// A DIY spec never touches a character pack's art files. It is stored per
// character pack in the config and replayed onto a freshly parsed SVG at
// render time:每个部件外面套一层 <g>，变换只加在这层上，所以动画 CSS
// 依然作用在原来的元素上，两者不会打架。
(function (root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.diyModel = api;
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  // Every adjustable group, its slider range and the SVG classes it drives.
  // Ranges are in viewBox units so a tweak means the same thing at any scale.
  const DIY_CONTROLS = Object.freeze([
    Object.freeze({
      part: 'body',
      label: '身体',
      fields: Object.freeze([
        Object.freeze({ key: 'width', label: '胖瘦', min: 0.7, max: 1.3, step: 0.01, kind: 'ratio' }),
        Object.freeze({ key: 'height', label: '高矮', min: 0.7, max: 1.3, step: 0.01, kind: 'ratio' }),
      ]),
    }),
    Object.freeze({
      part: 'fins',
      label: '鱼鳍',
      fields: Object.freeze([
        Object.freeze({ key: 'size', label: '大小', min: 0.5, max: 1.6, step: 0.01, kind: 'ratio' }),
        Object.freeze({ key: 'offsetX', label: '左右', min: -16, max: 16, step: 0.5, kind: 'length' }),
        Object.freeze({ key: 'offsetY', label: '上下', min: -16, max: 16, step: 0.5, kind: 'length' }),
      ]),
    }),
    Object.freeze({
      part: 'eyes',
      label: '眼睛',
      fields: Object.freeze([
        Object.freeze({ key: 'size', label: '大小', min: 0.6, max: 1.6, step: 0.01, kind: 'ratio' }),
        Object.freeze({ key: 'spacing', label: '间距', min: -12, max: 12, step: 0.5, kind: 'length' }),
        Object.freeze({ key: 'offsetY', label: '上下', min: -14, max: 14, step: 0.5, kind: 'length' }),
      ]),
    }),
    Object.freeze({
      part: 'mouth',
      label: '嘴巴',
      fields: Object.freeze([
        Object.freeze({ key: 'size', label: '大小', min: 0.6, max: 1.5, step: 0.01, kind: 'ratio' }),
        Object.freeze({ key: 'offsetY', label: '上下', min: -14, max: 14, step: 0.5, kind: 'length' }),
      ]),
    }),
    Object.freeze({
      part: 'nose',
      label: '鼻子',
      fields: Object.freeze([
        Object.freeze({ key: 'size', label: '大小', min: 0.6, max: 1.6, step: 0.01, kind: 'ratio' }),
        Object.freeze({ key: 'offsetY', label: '上下', min: -14, max: 14, step: 0.5, kind: 'length' }),
      ]),
    }),
  ]);

  // Which shape-preset groups exist, and the classes each one rewrites.
  const SHAPE_GROUPS = Object.freeze({
    body: Object.freeze({ label: '身体形状', targets: Object.freeze(['.body-shape']) }),
    fins: Object.freeze({ label: '鱼鳍形状', targets: Object.freeze(['.fin-left', '.fin-right']) }),
  });

  // A layer wraps one or more elements and pivots around a single one of them,
  // so a mirrored pair keeps its own centre instead of the pair's midpoint.
  const DIY_LAYERS = Object.freeze([
    Object.freeze({ key: 'body', pivot: '.body-shape', elements: Object.freeze(['.body-shape', '.body-shading']) }),
    Object.freeze({ key: 'finLeft', pivot: '.fin-left', elements: Object.freeze(['.fin-left']) }),
    Object.freeze({ key: 'finRight', pivot: '.fin-right', elements: Object.freeze(['.fin-right']) }),
    Object.freeze({ key: 'eyeLeft', pivot: '.eye-left', elements: Object.freeze(['.eye-left', '.tear-left']) }),
    Object.freeze({ key: 'eyeRight', pivot: '.eye-right', elements: Object.freeze(['.eye-right', '.tear-right']) }),
    Object.freeze({ key: 'mouth', pivot: '.mouth', elements: Object.freeze(['.mouth']) }),
    Object.freeze({ key: 'nose', pivot: '.nose', elements: Object.freeze(['.nose']) }),
  ]);

  const DEFAULT_SHAPE_ID = 'default';

  function buildDefaults() {
    const spec = {};
    for (const group of DIY_CONTROLS) {
      spec[group.part] = {};
      for (const field of group.fields) {
        spec[group.part][field.key] = field.kind === 'ratio' ? 1 : 0;
      }
    }
    for (const name of Object.keys(SHAPE_GROUPS)) {
      spec[name].shape = DEFAULT_SHAPE_ID;
    }
    return spec;
  }

  const DEFAULT_DIY = Object.freeze(buildDefaults());

  function defaultDiy() {
    return buildDefaults();
  }

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  // Sliders emit float noise; round to the step so saved configs stay tidy and
  // comparisons against the defaults actually hit.
  function quantize(value, step) {
    const steps = Math.round(value / step);
    return Number((steps * step).toFixed(4));
  }

  function normalizeShapeId(value) {
    if (typeof value !== 'string') return DEFAULT_SHAPE_ID;
    return /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(value) ? value : DEFAULT_SHAPE_ID;
  }

  // Anything unreadable falls back to the default rather than throwing: a bad
  // DIY value should never stop the pet from launching.
  function normalizeDiy(input) {
    const spec = defaultDiy();
    if (!input || typeof input !== 'object' || Array.isArray(input)) return spec;

    for (const group of DIY_CONTROLS) {
      const source = input[group.part];
      if (!source || typeof source !== 'object' || Array.isArray(source)) continue;
      for (const field of group.fields) {
        const value = Number(source[field.key]);
        if (!Number.isFinite(value)) continue;
        spec[group.part][field.key] = quantize(clamp(value, field.min, field.max), field.step);
      }
      if (SHAPE_GROUPS[group.part]) {
        spec[group.part].shape = normalizeShapeId(source.shape);
      }
    }
    return spec;
  }

  function isDefaultDiy(spec) {
    return JSON.stringify(normalizeDiy(spec)) === JSON.stringify(DEFAULT_DIY);
  }

  // Keyed by character pack id. Packs that never got customised are dropped so
  // the settings file doesn't accumulate no-op entries.
  function normalizeDiyMap(input) {
    const map = {};
    if (!input || typeof input !== 'object' || Array.isArray(input)) return map;
    for (const key of Object.keys(input)) {
      if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(key)) continue;
      const spec = normalizeDiy(input[key]);
      if (!isDefaultDiy(spec)) map[key] = spec;
    }
    return map;
  }

  // Translate the user-facing spec into per-layer scale/offset. Mirrored pairs
  // read the same slider with opposite horizontal signs.
  function layerTransform(layerKey, spec) {
    const diy = normalizeDiy(spec);
    switch (layerKey) {
      case 'body':
        return { scaleX: diy.body.width, scaleY: diy.body.height, dx: 0, dy: 0 };
      case 'finLeft':
        return { scaleX: diy.fins.size, scaleY: diy.fins.size, dx: -diy.fins.offsetX, dy: diy.fins.offsetY };
      case 'finRight':
        return { scaleX: diy.fins.size, scaleY: diy.fins.size, dx: diy.fins.offsetX, dy: diy.fins.offsetY };
      case 'eyeLeft':
        return { scaleX: diy.eyes.size, scaleY: diy.eyes.size, dx: -diy.eyes.spacing, dy: diy.eyes.offsetY };
      case 'eyeRight':
        return { scaleX: diy.eyes.size, scaleY: diy.eyes.size, dx: diy.eyes.spacing, dy: diy.eyes.offsetY };
      case 'mouth':
        return { scaleX: diy.mouth.size, scaleY: diy.mouth.size, dx: 0, dy: diy.mouth.offsetY };
      case 'nose':
        return { scaleX: diy.nose.size, scaleY: diy.nose.size, dx: 0, dy: diy.nose.offsetY };
      default:
        return { scaleX: 1, scaleY: 1, dx: 0, dy: 0 };
    }
  }

  function isIdentity(transform) {
    return transform.scaleX === 1 && transform.scaleY === 1 && transform.dx === 0 && transform.dy === 0;
  }

  function round(value) {
    return Number(value.toFixed(3));
  }

  function transformAttribute(transform, pivot) {
    if (isIdentity(transform)) return '';
    const tx = round(pivot.x + transform.dx);
    const ty = round(pivot.y + transform.dy);
    return `translate(${tx} ${ty}) scale(${round(transform.scaleX)} ${round(transform.scaleY)}) `
      + `translate(${round(-pivot.x)} ${round(-pivot.y)})`;
  }

  function findShapeOption(diyManifest, groupName, shapeId) {
    if (!diyManifest || !diyManifest.shapes) return null;
    const options = diyManifest.shapes[groupName];
    if (!Array.isArray(options)) return null;
    return options.find((option) => option && option.id === shapeId) || null;
  }

  function listShapeOptions(diyManifest, groupName) {
    if (!diyManifest || !diyManifest.shapes) return [];
    const options = diyManifest.shapes[groupName];
    return Array.isArray(options) ? options : [];
  }

  function supportsDiy(manifest) {
    return Boolean(manifest && manifest.diy && manifest.diy.enabled === true);
  }

  // --- DOM side -----------------------------------------------------------
  // Runs in the pet window and in the settings preview, on an SVG that was
  // just re-parsed from the pack, so it can freely replace nodes.

  function replaceGeometry(svgRoot, selector, pathData) {
    const target = svgRoot.querySelector(selector);
    if (!target || !pathData) return;

    const namespace = 'http://www.w3.org/2000/svg';
    const replacement = svgRoot.ownerDocument.createElementNS(namespace, 'path');
    for (const attribute of [...target.attributes]) {
      // Geometry attributes belong to the shape being replaced (an ellipse has
      // cx/rx, a path has d), so only presentation attributes carry over.
      if (['cx', 'cy', 'rx', 'ry', 'r', 'x', 'y', 'width', 'height', 'd', 'points'].includes(attribute.name)) continue;
      replacement.setAttribute(attribute.name, attribute.value);
    }
    replacement.setAttribute('d', pathData);
    target.replaceWith(replacement);
  }

  function applyShapes(svgRoot, spec, diyManifest) {
    const diy = normalizeDiy(spec);

    const bodyOption = findShapeOption(diyManifest, 'body', diy.body.shape);
    if (bodyOption) {
      replaceGeometry(svgRoot, '.body-shape', bodyOption.d);
      const shading = svgRoot.querySelector('.body-shading');
      // A reshaped body no longer matches the shading blob drawn for the
      // original silhouette, so presets can ask for it to be dropped.
      if (shading && bodyOption.hideShading === true) shading.remove();
    }

    const finOption = findShapeOption(diyManifest, 'fins', diy.fins.shape);
    if (finOption) {
      replaceGeometry(svgRoot, '.fin-left', finOption.left);
      replaceGeometry(svgRoot, '.fin-right', finOption.right);
    }
  }

  function wrapLayer(svgRoot, layer) {
    const existing = svgRoot.querySelector(`[data-diy-layer="${layer.key}"]`);
    if (existing) return existing;

    const nodes = layer.elements
      .map((selector) => svgRoot.querySelector(selector))
      .filter(Boolean);
    if (nodes.length === 0) return null;

    const namespace = 'http://www.w3.org/2000/svg';
    const group = svgRoot.ownerDocument.createElementNS(namespace, 'g');
    group.setAttribute('data-diy-layer', layer.key);
    // Insert where the first member sat so the paint order is untouched.
    nodes[0].replaceWith(group);
    for (const node of nodes) group.appendChild(node);
    return group;
  }

  function pivotOf(group, pivotSelector) {
    const target = group.querySelector(pivotSelector);
    if (!target || typeof target.getBBox !== 'function') return null;
    const box = target.getBBox();
    if (!box || (box.width === 0 && box.height === 0)) return null;
    return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
  }

  // Applies a whole spec to a live SVG root. Safe to call on art that has no
  // matching classes — missing parts are simply skipped.
  function applyDiyToSvg(svgRoot, spec, manifest) {
    if (!svgRoot || !supportsDiy(manifest)) return;
    const diyManifest = manifest.diy;
    applyShapes(svgRoot, spec, diyManifest);

    for (const layer of DIY_LAYERS) {
      const transform = layerTransform(layer.key, spec);
      const group = wrapLayer(svgRoot, layer);
      if (!group) continue;
      if (isIdentity(transform)) {
        group.removeAttribute('transform');
        continue;
      }
      const pivot = pivotOf(group, layer.pivot);
      if (!pivot) continue;
      group.setAttribute('transform', transformAttribute(transform, pivot));
    }
  }

  return Object.freeze({
    DEFAULT_DIY,
    DEFAULT_SHAPE_ID,
    DIY_CONTROLS,
    DIY_LAYERS,
    SHAPE_GROUPS,
    applyDiyToSvg,
    defaultDiy,
    findShapeOption,
    isDefaultDiy,
    layerTransform,
    listShapeOptions,
    normalizeDiy,
    normalizeDiyMap,
    supportsDiy,
    transformAttribute,
  });
}));
