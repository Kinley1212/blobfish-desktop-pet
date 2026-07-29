class TaskLeasePollEpoch {
  constructor() {
    this.epoch = 0;
  }

  invalidate() {
    this.epoch += 1;
  }

  async scanAndApply(readRecords, applyRecords) {
    const startedAtEpoch = this.epoch;
    const records = await readRecords();
    if (startedAtEpoch !== this.epoch) return false;
    applyRecords(records);
    return true;
  }
}

module.exports = { TaskLeasePollEpoch };
