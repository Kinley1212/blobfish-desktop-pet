const RARITY_FACTORS = Object.freeze({ common: 1, uncommon: 0.35, rare: 0.06 });
const CONTEXT_KEY_PATTERN = /^[A-Za-z][A-Za-z0-9]*$/;
const KNOWN_PROVIDERS = new Set(['codex', 'claude-code']);

function hasValue(context, key) {
  return Object.prototype.hasOwnProperty.call(context, key) && context[key] !== undefined && context[key] !== null;
}

function isNonNegativeSafeInteger(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

function conditionRule(validate, matches) {
  return Object.freeze({ validate, matches });
}

const CONDITION_RULES = Object.freeze({
  requires: conditionRule(
    (value) => Array.isArray(value)
      && value.length <= 32
      && value.every((key) => typeof key === 'string' && CONTEXT_KEY_PATTERN.test(key)),
    (value, context) => value.every((key) => hasValue(context, key)),
  ),
  batteryEquals: conditionRule(
    (value) => Number.isInteger(value) && value >= 0 && value <= 100,
    (value, context) => context.battery === value,
  ),
  activeCountMin: conditionRule(
    isNonNegativeSafeInteger,
    (value, context) => context.activeCount >= value,
  ),
  remainingMin: conditionRule(
    isNonNegativeSafeInteger,
    (value, context) => context.remaining >= value,
  ),
  remainingEquals: conditionRule(
    isNonNegativeSafeInteger,
    (value, context) => context.remaining === value,
  ),
  durationMinSeconds: conditionRule(
    isNonNegativeSafeInteger,
    (value, context) => context.durationSeconds >= value,
  ),
  lockedMinSeconds: conditionRule(
    isNonNegativeSafeInteger,
    (value, context) => context.lockedSeconds >= value,
  ),
  clickCountMin: conditionRule(
    isNonNegativeSafeInteger,
    (value, context) => context.clickCount >= value,
  ),
  provider: conditionRule(
    (value) => typeof value === 'string' && KNOWN_PROVIDERS.has(value),
    (value, context) => context.provider === value,
  ),
  weekdays: conditionRule(
    (value) => Array.isArray(value)
      && value.length <= 7
      && value.every((weekday) => Number.isInteger(weekday) && weekday >= 0 && weekday <= 6),
    (value, context) => value.includes(context.weekday),
  ),
  hourMin: conditionRule(
    (value) => Number.isInteger(value) && value >= 0 && value <= 23,
    (value, context) => context.hour >= value,
  ),
  hourMax: conditionRule(
    (value) => Number.isInteger(value) && value >= 0 && value <= 23,
    (value, context) => context.hour <= value,
  ),
});

function getConditionValidationError(conditions) {
  if (conditions === undefined) return null;
  if (conditions === null || typeof conditions !== 'object' || Array.isArray(conditions)) {
    return 'conditions must be an object';
  }

  for (const [key, value] of Object.entries(conditions)) {
    if (!Object.prototype.hasOwnProperty.call(CONDITION_RULES, key)) {
      return `an unsupported condition: ${key}`;
    }
    if (!CONDITION_RULES[key].validate(value)) {
      return `an invalid condition: ${key}`;
    }
  }

  if (
    conditions.hourMin !== undefined
    && conditions.hourMax !== undefined
    && conditions.hourMin > conditions.hourMax
  ) {
    return 'an invalid hour range: hourMin cannot exceed hourMax';
  }
  return null;
}

function matchesConditions(conditions = {}, context = {}) {
  if (getConditionValidationError(conditions) !== null) return false;
  return Object.entries(conditions).every(([key, value]) => CONDITION_RULES[key].matches(value, context));
}

function renderTemplate(text, context) {
  let unresolved = false;
  const rendered = text.replace(/\{([A-Za-z][A-Za-z0-9]*)\}/g, (_match, key) => {
    if (!hasValue(context, key)) {
      unresolved = true;
      return '';
    }
    const value = context[key];
    if (!['string', 'number', 'boolean'].includes(typeof value)) {
      unresolved = true;
      return '';
    }
    return String(value);
  });
  return unresolved ? null : rendered;
}

class PhraseEngine {
  constructor(phrases, options = {}) {
    if (!Array.isArray(phrases)) throw new TypeError('PhraseEngine requires a phrase array');
    this.phrases = phrases;
    this.random = options.random || Math.random;
    this.now = options.now || Date.now;
    this.historyLimit = options.historyLimit || 20;
    this.history = [];
    this.lastUsedAt = new Map();
  }

  select(event, context = {}) {
    const now = this.now();
    const candidates = this.phrases
      .filter((phrase) => phrase.event === event)
      .filter((phrase) => matchesConditions(phrase.conditions, context))
      .map((phrase) => ({ phrase, text: renderTemplate(phrase.text, context) }))
      .filter(({ phrase, text }) => {
        if (text === null) return false;
        const lastUsed = this.lastUsedAt.get(phrase.id);
        return lastUsed === undefined || now - lastUsed >= (phrase.cooldownMs || 0);
      });

    if (candidates.length === 0) return null;
    const unseen = candidates.filter(({ phrase }) => !this.history.includes(phrase.id));
    const pool = unseen.length > 0 ? unseen : candidates;
    const weighted = pool.map((entry) => ({
      ...entry,
      effectiveWeight: (entry.phrase.weight || 1) * (RARITY_FACTORS[entry.phrase.rarity || 'common'] || 1),
    }));
    const totalWeight = weighted.reduce((total, entry) => total + entry.effectiveWeight, 0);
    let cursor = Math.min(Math.max(this.random(), 0), 0.999999999999) * totalWeight;
    let chosen = weighted[weighted.length - 1];
    for (const entry of weighted) {
      cursor -= entry.effectiveWeight;
      if (cursor < 0) {
        chosen = entry;
        break;
      }
    }

    this.lastUsedAt.set(chosen.phrase.id, now);
    this.history.push(chosen.phrase.id);
    if (this.history.length > this.historyLimit) this.history.shift();
    return Object.freeze({ ...chosen.phrase, text: chosen.text });
  }
}

module.exports = {
  CONDITION_RULES,
  PhraseEngine,
  getConditionValidationError,
  matchesConditions,
  renderTemplate,
};
