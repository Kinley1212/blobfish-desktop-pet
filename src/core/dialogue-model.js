// A tiny branching-choice dialogue system.
//
// The fish says a line; you pick one of a few replies; it reacts (a line plus
// an expression) and the conversation either ends or branches to another node.
// Everything is data — a dialogue pack is a flat map of nodes — so new
// conversations are content, not code. It stays entirely local: no network,
// no model, just a hand-written tree.
(function (root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.dialogueModel = api;
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const NODE_ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
  const FACE_ID_PATTERN = /^face-[a-z0-9]+(?:-[a-z0-9]+)*$/;
  const GAMES = Object.freeze(['rps', 'dice', 'riddle']);
  const MAX_PROMPT = 140;
  const MAX_REPLY = 200;
  const MAX_LABEL = 30;

  function validateOption(option, nodeId, index, nodeIds) {
    const where = `dialogue node "${nodeId}" option ${index}`;
    if (!option || typeof option !== 'object' || Array.isArray(option)) {
      throw new Error(`${where} must be an object`);
    }
    if (typeof option.label !== 'string' || option.label.trim().length === 0 || option.label.length > MAX_LABEL) {
      throw new Error(`${where} needs a short label`);
    }
    if (option.reply !== undefined && (typeof option.reply !== 'string' || option.reply.length > MAX_REPLY)) {
      throw new Error(`${where} reply must be a short string`);
    }
    if (option.face !== undefined && (typeof option.face !== 'string' || !FACE_ID_PATTERN.test(option.face))) {
      throw new Error(`${where} face must be a face id`);
    }
    if (option.next !== undefined) {
      if (typeof option.next !== 'string' || !nodeIds.has(option.next)) {
        throw new Error(`${where} points to a missing node: ${option.next}`);
      }
    }
    // An option can hand off to a mini-game instead of another line.
    if (option.game !== undefined && !GAMES.includes(option.game)) {
      throw new Error(`${where} names an unknown game: ${option.game}`);
    }
  }

  function validateDialogue(pack) {
    if (!pack || typeof pack !== 'object' || Array.isArray(pack)) {
      throw new Error('Dialogue pack must be an object');
    }
    const { nodes } = pack;
    if (!nodes || typeof nodes !== 'object' || Array.isArray(nodes)) {
      throw new Error('Dialogue pack must have a nodes object');
    }
    const ids = Object.keys(nodes);
    if (ids.length === 0 || ids.length > 200) {
      throw new Error('Dialogue pack must have 1-200 nodes');
    }
    const nodeIds = new Set(ids);
    let openers = 0;
    for (const id of ids) {
      if (!NODE_ID_PATTERN.test(id)) throw new Error(`Invalid dialogue node id: ${id}`);
      const node = nodes[id];
      if (!node || typeof node !== 'object' || Array.isArray(node)) {
        throw new Error(`Dialogue node "${id}" must be an object`);
      }
      if (typeof node.prompt !== 'string' || node.prompt.trim().length === 0 || node.prompt.length > MAX_PROMPT) {
        throw new Error(`Dialogue node "${id}" needs a short prompt`);
      }
      if (node.opener !== undefined && typeof node.opener !== 'boolean') {
        throw new Error(`Dialogue node "${id}" opener must be a boolean`);
      }
      if (node.opener) openers += 1;
      if (!Array.isArray(node.options) || node.options.length === 0 || node.options.length > 4) {
        throw new Error(`Dialogue node "${id}" must have 1-4 options`);
      }
      node.options.forEach((option, index) => validateOption(option, id, index, nodeIds));
    }
    if (openers === 0) throw new Error('Dialogue pack needs at least one opener node');
    return pack;
  }

  function listOpeners(pack) {
    if (!pack || !pack.nodes) return [];
    return Object.keys(pack.nodes).filter((id) => pack.nodes[id].opener === true);
  }

  function getNode(pack, id) {
    if (!pack || !pack.nodes) return null;
    return pack.nodes[id] || null;
  }

  // A conversation always begins on a random opener. `random` is injectable so
  // tests can pin the pick.
  function pickOpenerId(pack, random = Math.random) {
    const openers = listOpeners(pack);
    if (openers.length === 0) return null;
    return openers[Math.min(openers.length - 1, Math.floor(random() * openers.length))];
  }

  // Turns a chosen option into what the fish should do and where to go next.
  function resolveChoice(pack, nodeId, optionIndex) {
    const node = getNode(pack, nodeId);
    if (!node) return null;
    const option = node.options[optionIndex];
    if (!option) return null;
    return {
      reply: option.reply || null,
      face: option.face || null,
      nextId: option.next || null,
      game: option.game || null,
      // With no follow-up node and no game, the topic is over after this reply.
      ended: !option.next && !option.game,
    };
  }

  return Object.freeze({
    FACE_ID_PATTERN,
    NODE_ID_PATTERN,
    getNode,
    listOpeners,
    pickOpenerId,
    resolveChoice,
    validateDialogue,
  });
}));
