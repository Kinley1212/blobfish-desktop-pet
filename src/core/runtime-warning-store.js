class RuntimeWarningStore {
  constructor() {
    this.messages = new Map();
  }

  set(key, message) {
    if (typeof key !== 'string' || !key) throw new TypeError('Warning key is required');
    if (typeof message !== 'string' || !message.trim()) throw new TypeError('Warning message is required');
    this.messages.set(key, message.trim());
  }

  clear(key) {
    this.messages.delete(key);
  }

  getMessage(...additionalMessages) {
    return [...this.messages.values(), ...additionalMessages]
      .filter((message) => typeof message === 'string' && message.trim())
      .join('\n') || null;
  }
}

module.exports = { RuntimeWarningStore };
