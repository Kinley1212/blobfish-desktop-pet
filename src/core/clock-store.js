const fs = require('fs');
const path = require('path');
const {
  DEFAULT_CLOCK_STATE,
  validateClockState,
} = require('./clock-engine');

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

class ClockStore {
  constructor(directory, options = {}) {
    this.directory = directory;
    this.filePath = path.join(directory, options.filename || 'clock-state.json');
    this.state = clone(DEFAULT_CLOCK_STATE);
    this.loadWarning = null;
  }

  load() {
    this.loadWarning = null;
    if (!fs.existsSync(this.filePath)) return this.get();
    try {
      this.state = validateClockState(JSON.parse(fs.readFileSync(this.filePath, 'utf8')));
    } catch (error) {
      this.state = clone(DEFAULT_CLOCK_STATE);
      this.loadWarning = `闹钟与计时记录无效，已临时使用空记录：${error.message}`;
    }
    return this.get();
  }

  get() {
    return clone(this.state);
  }

  save(nextState) {
    const validated = validateClockState(nextState);
    fs.mkdirSync(this.directory, { recursive: true, mode: 0o700 });
    const tempPath = `${this.filePath}.${process.pid}.tmp`;
    try {
      fs.writeFileSync(tempPath, `${JSON.stringify(validated, null, 2)}\n`, {
        encoding: 'utf8',
        mode: 0o600,
      });
      fs.renameSync(tempPath, this.filePath);
    } finally {
      if (fs.existsSync(tempPath)) fs.unlinkSync(tempPath);
    }
    this.state = validated;
    this.loadWarning = null;
    return this.get();
  }

  update(mutator) {
    if (typeof mutator !== 'function') throw new TypeError('ClockStore.update requires a mutator');
    const nextState = mutator(this.get());
    return this.save(nextState);
  }
}

module.exports = {
  ClockStore,
};
