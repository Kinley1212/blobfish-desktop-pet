// Picks a fleeting expression to wear while the pet is saying something.
//
// Speech already carries the event that produced it, so the mood can be read
// straight off that name — no extra plumbing between the main process and the
// pet window. The face only changes some of the time: an expression on every
// single line stops reading as a reaction and starts reading as a twitch.
(function (root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.expressionMoods = api;
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  // Longest prefix wins, so a specific event can override its family.
  const MOODS = Object.freeze([
    Object.freeze({ prefix: 'interaction.click', chance: 0.85, faces: ['face-cry', 'face-panic', 'face-shocked', 'face-angry'] }),
    Object.freeze({ prefix: 'interaction.pettingLots', chance: 0.9, faces: ['face-love', 'face-coy', 'face-sparkle'] }),
    Object.freeze({ prefix: 'interaction.pettingMore', chance: 0.75, faces: ['face-coy', 'face-happy', 'face-smug'] }),
    Object.freeze({ prefix: 'interaction.petting', chance: 0.6, faces: ['face-coy', 'face-smug', 'face-blank'] }),
    Object.freeze({ prefix: 'interaction.goodbye', chance: 0.6, faces: ['face-wink', 'face-relieved'] }),
    Object.freeze({ prefix: 'interaction.', chance: 0.3, faces: ['face-blank', 'face-smug', 'face-happy'] }),

    Object.freeze({ prefix: 'idle.lateNight', chance: 0.6, faces: ['face-sleepy', 'face-dizzy', 'face-blank'] }),
    Object.freeze({ prefix: 'idle.longSession', chance: 0.6, faces: ['face-dizzy', 'face-annoyed', 'face-sleepy'] }),
    Object.freeze({ prefix: 'idle.weekend', chance: 0.45, faces: ['face-relieved', 'face-happy', 'face-smug'] }),
    Object.freeze({ prefix: 'idle.', chance: 0.3, faces: ['face-blank', 'face-sleepy', 'face-smug', 'face-annoyed'] }),

    Object.freeze({ prefix: 'schedule.lunchSoon', chance: 0.8, faces: ['face-hungry', 'face-sparkle', 'face-happy'] }),
    Object.freeze({ prefix: 'schedule.offWork', chance: 0.7, faces: ['face-relieved', 'face-sparkle', 'face-happy'] }),
    Object.freeze({ prefix: 'schedule.halfHour', chance: 0.4, faces: ['face-annoyed', 'face-blank', 'face-sleepy'] }),
    Object.freeze({ prefix: 'schedule.', chance: 0.4, faces: ['face-blank', 'face-happy'] }),

    Object.freeze({ prefix: 'agent.failed', chance: 0.9, faces: ['face-panic', 'face-shocked', 'face-pitiful'] }),
    Object.freeze({ prefix: 'agent.needsInput', chance: 0.7, faces: ['face-pitiful', 'face-shocked', 'face-coy'] }),
    Object.freeze({ prefix: 'agent.allCompleted', chance: 0.85, faces: ['face-proud', 'face-sparkle', 'face-relieved'] }),
    Object.freeze({ prefix: 'agent.completed', chance: 0.6, faces: ['face-happy', 'face-proud', 'face-sparkle'] }),
    Object.freeze({ prefix: 'agent.longRunning', chance: 0.5, faces: ['face-sleepy', 'face-annoyed', 'face-dizzy'] }),
    Object.freeze({ prefix: 'agent.', chance: 0.3, faces: ['face-blank', 'face-happy', 'face-smug'] }),

    Object.freeze({ prefix: 'system.error', chance: 0.95, faces: ['face-panic', 'face-shocked', 'face-dizzy'] }),
    Object.freeze({ prefix: 'system.battery', chance: 0.7, faces: ['face-panic', 'face-pitiful', 'face-dizzy'] }),
    Object.freeze({ prefix: 'system.unlocked', chance: 0.5, faces: ['face-happy', 'face-sparkle', 'face-sleepy'] }),
    Object.freeze({ prefix: 'system.', chance: 0.35, faces: ['face-blank', 'face-happy'] }),

    Object.freeze({ prefix: 'calendar.busyDay', chance: 0.6, faces: ['face-dizzy', 'face-panic', 'face-annoyed'] }),
    Object.freeze({ prefix: 'calendar.freeGap', chance: 0.5, faces: ['face-relieved', 'face-happy'] }),
    Object.freeze({ prefix: 'calendar.', chance: 0.4, faces: ['face-shocked', 'face-blank', 'face-panic'] }),

    Object.freeze({ prefix: 'startup.', chance: 0.6, faces: ['face-happy', 'face-sleepy', 'face-sparkle'] }),
    // Rare lines are already a treat, so they almost always come with a face.
    Object.freeze({ prefix: 'rare.', chance: 0.9, faces: ['face-sparkle', 'face-love', 'face-proud', 'face-dizzy', 'face-wink'] }),
  ]);

  function findMood(event) {
    if (typeof event !== 'string') return null;
    let best = null;
    for (const mood of MOODS) {
      if (!event.startsWith(mood.prefix)) continue;
      if (!best || mood.prefix.length > best.prefix.length) best = mood;
    }
    return best;
  }

  // `random` is injectable so tests can pin the outcome; it is called at most
  // twice — once to decide whether to react, once to choose the face.
  function pickExpression(event, options = {}) {
    const mood = findMood(event);
    if (!mood) return null;

    const random = typeof options.random === 'function' ? options.random : Math.random;
    const available = Array.isArray(options.available) ? options.available : null;
    if (random() >= mood.chance) return null;

    // A pack may not ship every face, so choose from what actually exists.
    const faces = available ? mood.faces.filter((face) => available.includes(face)) : mood.faces;
    if (faces.length === 0) return null;
    return faces[Math.min(faces.length - 1, Math.floor(random() * faces.length))];
  }

  return Object.freeze({ MOODS, findMood, pickExpression });
}));
