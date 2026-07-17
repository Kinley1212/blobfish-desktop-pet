const RARITY_FACTORS = Object.freeze({ common: 1, uncommon: 0.35, rare: 0.06 });

function hasValue(context, key) {
  return Object.prototype.hasOwnProperty.call(context, key) && context[key] !== undefined && context[key] !== null;
}

function matchesConditions(conditions = {}, context = {}) {
  if (Array.isArray(conditions.requires) && conditions.requires.some((key) => !hasValue(context, key))) return false;
  if (conditions.batteryEquals !== undefined && context.battery !== conditions.batteryEquals) return false;
  if (conditions.activeCountMin !== undefined && !(context.activeCount >= conditions.activeCountMin)) return false;
  if (conditions.remainingMin !== undefined && !(context.remaining >= conditions.remainingMin)) return false;
  if (conditions.remainingEquals !== undefined && context.remaining !== conditions.remainingEquals) return false;
  if (conditions.durationMinSeconds !== undefined && !(context.durationSeconds >= conditions.durationMinSeconds)) return false;
  if (conditions.lockedMinSeconds !== undefined && !(context.lockedSeconds >= conditions.lockedMinSeconds)) return false;
  if (conditions.clickCountMin !== undefined && !(context.clickCount >= conditions.clickCountMin)) return false;
  if (conditions.provider !== undefined && context.provider !== conditions.provider) return false;
  if (Array.isArray(conditions.weekdays) && !conditions.weekdays.includes(context.weekday)) return false;
  if (conditions.hourMin !== undefined && !(context.hour >= conditions.hourMin)) return false;
  if (conditions.hourMax !== undefined && !(context.hour <= conditions.hourMax)) return false;
  return true;
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
  PhraseEngine,
  matchesConditions,
  renderTemplate,
};
