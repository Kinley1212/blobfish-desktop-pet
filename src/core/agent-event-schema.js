const PROVIDERS = new Set(['codex', 'claude-code']);
const EVENTS = new Set(['started', 'running', 'needs_input', 'completed', 'failed']);
const IDENTIFIER_PATTERN = /^[A-Za-z0-9._:@+-]{1,256}$/;

function validateAgentEvent(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Agent event must be an object');
  if (input.version !== 1) throw new Error('Agent event version is unsupported');
  if (!PROVIDERS.has(input.provider)) throw new Error('Agent event provider is unsupported');
  if (!EVENTS.has(input.event)) throw new Error('Agent event type is unsupported');
  if (!IDENTIFIER_PATTERN.test(input.sessionId || '')) throw new Error('Agent event sessionId is invalid');
  if (input.turnId !== undefined && !IDENTIFIER_PATTERN.test(input.turnId)) {
    throw new Error('Agent event turnId is invalid');
  }
  if (input.title !== undefined && (
    typeof input.title !== 'string' || input.title.length === 0 || input.title.length > 120 || /[\u0000-\u001f\u007f]/.test(input.title)
  )) {
    throw new Error('Agent event title is invalid');
  }
  if (input.timestamp !== undefined && (!Number.isFinite(input.timestamp) || input.timestamp < 0)) {
    throw new Error('Agent event timestamp is invalid');
  }

  return Object.freeze({
    version: 1,
    provider: input.provider,
    event: input.event,
    sessionId: input.sessionId,
    turnId: input.turnId || null,
    title: input.title || null,
    timestamp: input.timestamp || Date.now(),
  });
}

module.exports = {
  EVENTS,
  PROVIDERS,
  validateAgentEvent,
};
