const assert = require('node:assert/strict');
const test = require('node:test');

const { SPEECH_DURATION_MS } = require('../src/core/speech-timing');

test('idle chatter and agent lifecycle lines remain visible for seven seconds', () => {
  assert.equal(SPEECH_DURATION_MS.idleChatter, 7000);
  assert.equal(SPEECH_DURATION_MS.agentLifecycle, 7000);
});
