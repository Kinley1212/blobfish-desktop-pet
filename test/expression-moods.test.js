const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');

const { MOODS, findMood, pickExpression } = require('../src/core/expression-moods');
const { loadAccessoryCatalog } = require('../src/core/accessory-loader');

const accessoriesRoot = path.join(__dirname, '..', 'src', 'packs', 'accessories');

// Always reacts, and always takes the first face of the chosen mood.
const alwaysFirst = () => 0;
// Never reacts: the first draw already fails the chance check.
const never = () => 0.999999;

test('the most specific event prefix wins over its family', () => {
  assert.equal(findMood('interaction.pettingLots').prefix, 'interaction.pettingLots');
  assert.equal(findMood('interaction.pettingMore').prefix, 'interaction.pettingMore');
  assert.equal(findMood('interaction.petting').prefix, 'interaction.petting');
  assert.equal(findMood('interaction.menuOpen').prefix, 'interaction.');
  assert.equal(findMood('schedule.offWorkSoon').prefix, 'schedule.offWork');
});

test('an unknown event asks for no expression at all', () => {
  assert.equal(findMood('nothing.like.this'), null);
  assert.equal(findMood(undefined), null);
  assert.equal(pickExpression('nothing.like.this', { random: alwaysFirst }), null);
});

test('a line only sometimes pulls a face', () => {
  assert.equal(pickExpression('idle.chatter', { random: never }), null, 'a failed roll leaves the face alone');
  assert.equal(pickExpression('idle.chatter', { random: alwaysFirst }), 'face-blank');
});

test('the mood suits the moment', () => {
  assert.equal(pickExpression('interaction.click', { random: alwaysFirst }), 'face-cry');
  assert.equal(pickExpression('system.error', { random: alwaysFirst }), 'face-panic');
  assert.equal(pickExpression('schedule.lunchSoon', { random: alwaysFirst }), 'face-hungry');
  assert.equal(pickExpression('agent.allCompleted', { random: alwaysFirst }), 'face-proud');
  assert.equal(pickExpression('idle.lateNight', { random: alwaysFirst }), 'face-sleepy');
  assert.equal(pickExpression('interaction.pettingLots', { random: alwaysFirst }), 'face-love');
});

test('something breaking almost always shows on the face, idle chatter rarely does', () => {
  assert.ok(findMood('system.error').chance > 0.9);
  assert.ok(findMood('idle.').chance <= 0.35, 'ordinary muttering should mostly keep a straight face');
});

test('being hit and being petted land on a coin flip', () => {
  // Deliberately even: these fire constantly while you play with the pet, so
  // reacting every time reads as a twitch rather than a reaction.
  for (const event of ['interaction.click', 'interaction.petting', 'interaction.pettingMore', 'interaction.pettingLots']) {
    assert.equal(findMood(event).chance, 0.5, `${event} should be an even chance`);
  }
});

test('a face the pack does not ship is never chosen', () => {
  assert.equal(
    pickExpression('system.error', { random: alwaysFirst, available: ['face-shocked', 'face-dizzy'] }),
    'face-shocked',
    'the first face that actually exists is used',
  );
  assert.equal(
    pickExpression('system.error', { random: alwaysFirst, available: ['face-happy'] }),
    null,
    'no candidate available means no expression',
  );
  assert.equal(pickExpression('system.error', { random: alwaysFirst, available: [] }), null);
});

test('a roll at the very top of its range still lands on a real face', () => {
  // Math.random() can return values arbitrarily close to 1, which must not
  // index past the end of the candidate list. Roll a sure reaction, then the
  // largest possible value when choosing between the faces.
  const sureThenHighest = () => {
    const values = [0, 0.99999999];
    return values[sureThenHighest.calls++] ?? 0.99999999;
  };

  for (const mood of MOODS) {
    sureThenHighest.calls = 0;
    const picked = pickExpression(mood.prefix, { random: sureThenHighest });
    assert.equal(picked, mood.faces[mood.faces.length - 1], `${mood.prefix} should land on its last face`);
  }
});

test('every face a mood can ask for is actually bundled', () => {
  const shipped = new Set(loadAccessoryCatalog(accessoriesRoot).filter((item) => item.slot === 'face').map((item) => item.id));

  for (const mood of MOODS) {
    for (const face of mood.faces) {
      assert.ok(shipped.has(face), `${mood.prefix} asks for ${face}, which is not in the wardrobe`);
    }
  }
});

test('every speech family the language packs use has a mood', () => {
  const families = [
    'interaction.click', 'interaction.petting', 'interaction.goodbye', 'interaction.menuOpen',
    'idle.chatter', 'idle.lateNight', 'idle.weekend', 'idle.longSession',
    'schedule.halfHour', 'schedule.lunchSoon', 'schedule.offWorkSoon',
    'agent.started', 'agent.completed', 'agent.failed', 'agent.needsInput', 'agent.allCompleted',
    'system.error', 'system.battery', 'system.unlocked',
    'calendar.upcoming', 'calendar.busyDay', 'startup.workdayMorning', 'rare.friday',
  ];

  for (const event of families) {
    assert.ok(findMood(event), `${event} has no mood mapped`);
  }
});
