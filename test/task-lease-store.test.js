const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  readActiveTaskLeases,
  readTaskLeases,
  readTaskLeasesAsync,
  removeLease,
} = require('../src/core/task-lease-store');

function leaseName(provider, sessionId) {
  return `${crypto.createHash('sha256').update(`${provider}\0${sessionId}`).digest('hex')}.json`;
}

function writeLease(directory, value) {
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  const filePath = path.join(directory, leaseName(value.provider, value.sessionId));
  fs.writeFileSync(filePath, JSON.stringify(value), { mode: 0o600 });
  return filePath;
}

test('restores valid active and waiting leases without replaying terminal tombstones as tasks', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-lease-store-'));
  const now = 50_000;
  try {
    writeLease(root, {
      version: 1,
      provider: 'codex',
      event: 'running',
      sessionId: 'running-session',
      turnId: 'turn-1',
      title: '正在修复任务',
      timestamp: now - 500,
      startedAt: now - 5_000,
    });
    writeLease(root, {
      version: 1,
      provider: 'claude-code',
      event: 'needs_input',
      sessionId: 'waiting-session',
      timestamp: now - 1_000,
      startedAt: now - 8_000,
    });
    const tombstonePath = writeLease(root, {
      version: 1,
      provider: 'codex',
      event: 'ended',
      sessionId: 'ended-session',
      timestamp: now - 100,
    });

    const records = readTaskLeases(root, { now });
    assert.deepEqual(records.map((record) => record.event.event), ['needs_input', 'running', 'ended']);
    assert.deepEqual(
      readActiveTaskLeases(root, { now }).map((event) => event.sessionId).sort(),
      ['running-session', 'waiting-session'],
    );
    const running = records.find((record) => record.event.sessionId === 'running-session').event;
    assert.equal(running.title, '正在修复任务');
    assert.equal(running.startedAt, now - 5_000);

    removeLease(tombstonePath);
    assert.equal(fs.existsSync(tombstonePath), false);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('ignores expired, oversized and malformed records without deleting a concurrent producer path', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-lease-expiry-'));
  const now = 100_000;
  try {
    const staleActive = writeLease(root, {
      version: 1,
      provider: 'codex',
      event: 'running',
      sessionId: 'stale-active',
      timestamp: now - 2_001,
    });
    const staleTerminal = writeLease(root, {
      version: 1,
      provider: 'codex',
      event: 'ended',
      sessionId: 'stale-terminal',
      timestamp: now - 1_001,
    });
    const malformed = path.join(root, `${'a'.repeat(64)}.json`);
    fs.writeFileSync(malformed, '{broken', { mode: 0o600 });
    const oversized = path.join(root, `${'b'.repeat(64)}.json`);
    fs.writeFileSync(oversized, 'x'.repeat(17 * 1024), { mode: 0o600 });

    assert.deepEqual(readTaskLeases(root, {
      now,
      activeMaxAgeMs: 2_000,
      waitingMaxAgeMs: 2_000,
      terminalMaxAgeMs: 1_000,
    }), []);
    for (const filePath of [staleActive, staleTerminal, malformed, oversized]) {
      assert.equal(fs.existsSync(filePath), true);
    }

    writeLease(root, {
      version: 1,
      provider: 'codex',
      event: 'started',
      sessionId: 'stale-active',
      turnId: 'replacement-turn',
      timestamp: now,
    });
    const replacement = readTaskLeases(root, {
      now,
      activeMaxAgeMs: 2_000,
      waitingMaxAgeMs: 2_000,
      terminalMaxAgeMs: 1_000,
    });
    assert.equal(replacement.length, 1);
    assert.equal(replacement[0].event.turnId, 'replacement-turn');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('reads the newest lease files when the private directory exceeds its bounded scan size', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-lease-limit-'));
  const now = 1_000_000;
  try {
    for (let index = 0; index <= 256; index += 1) {
      const filePath = path.join(root, `${index.toString(16).padStart(64, '0')}.json`);
      fs.writeFileSync(filePath, JSON.stringify({
        version: 1,
        provider: 'codex',
        event: 'running',
        sessionId: `session-${index}`,
        turnId: `turn-${index}`,
        timestamp: now - 1,
      }), { mode: 0o600 });
      const modifiedAt = new Date((index + 1) * 1000);
      fs.utimesSync(filePath, modifiedAt, modifiedAt);
    }

    const records = readTaskLeases(root, { now });
    assert.equal(records.length, 256);
    assert.equal(records.some((record) => record.event.sessionId === 'session-0'), false);
    assert.equal(records.some((record) => record.event.sessionId === 'session-256'), true);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('expired or malformed files do not consume the valid lease scan limit', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-lease-invalid-limit-'));
  const now = 2_000_000;
  try {
    const validPath = writeLease(root, {
      version: 1,
      provider: 'codex',
      event: 'running',
      sessionId: 'still-active',
      turnId: 'active-turn',
      timestamp: now - 100,
    });
    fs.utimesSync(validPath, new Date(1000), new Date(1000));

    for (let index = 0; index < 256; index += 1) {
      const name = `${(index + 1024).toString(16).padStart(64, '0')}.json`;
      const filePath = path.join(root, name);
      fs.writeFileSync(filePath, '{broken', { mode: 0o600 });
      const modifiedAt = new Date((index + 2) * 1000);
      fs.utimesSync(filePath, modifiedAt, modifiedAt);
    }

    const records = readTaskLeases(root, { now });
    assert.equal(records.length, 1);
    assert.equal(records[0].event.sessionId, 'still-active');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('propagates unexpected file read errors instead of treating them as malformed data', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-lease-error-'));
  const now = 400_000;
  const originalReadFileSync = fs.readFileSync;
  try {
    writeLease(root, {
      version: 1,
      provider: 'codex',
      event: 'running',
      sessionId: 'io-error-session',
      timestamp: now,
    });
    fs.readFileSync = (target, ...args) => {
      if (typeof target === 'number') {
        const error = new Error('simulated lease read failure');
        error.code = 'EIO';
        throw error;
      }
      return originalReadFileSync(target, ...args);
    };
    assert.throws(
      () => readTaskLeases(root, { now }),
      /simulated lease read failure/,
    );
  } finally {
    fs.readFileSync = originalReadFileSync;
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('a new turn can atomically replace a retained terminal tombstone', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-lease-replace-'));
  const now = 200_000;
  try {
    const filePath = writeLease(root, {
      version: 1,
      provider: 'claude-code',
      event: 'ended',
      sessionId: 'same-session',
      turnId: 'old-turn',
      timestamp: now - 100,
    });
    const terminalRecord = readTaskLeases(root, { now })[0];
    assert.equal(terminalRecord.event.event, 'ended');

    writeLease(root, {
      version: 1,
      provider: 'claude-code',
      event: 'started',
      sessionId: 'same-session',
      turnId: 'new-turn',
      timestamp: now,
      startedAt: now,
    });
    assert.equal(terminalRecord.filePath, filePath);
    const current = readTaskLeases(root, { now })[0].event;
    assert.equal(current.event, 'started');
    assert.equal(current.turnId, 'new-turn');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('startup polling discards an opened lease when the producer atomically replaces its path', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-lease-sync-replace-'));
  const now = 250_000;
  const originalReadFileSync = fs.readFileSync;
  let replaced = false;
  try {
    const filePath = writeLease(root, {
      version: 1,
      provider: 'codex',
      event: 'running',
      sessionId: 'sync-replaced-session',
      turnId: 'active-turn',
      timestamp: now - 100,
    });
    const replacementPath = `${filePath}.replacement`;

    fs.readFileSync = (target, ...args) => {
      const contents = originalReadFileSync(target, ...args);
      if (typeof target === 'number' && !replaced) {
        fs.writeFileSync(replacementPath, JSON.stringify({
          version: 1,
          provider: 'codex',
          event: 'ended',
          sessionId: 'sync-replaced-session',
          turnId: 'active-turn',
          timestamp: now,
        }), { mode: 0o600 });
        fs.renameSync(replacementPath, filePath);
        replaced = true;
      }
      return contents;
    };

    const racedRecords = readTaskLeases(root, { now });
    assert.equal(replaced, true);
    assert.deepEqual(racedRecords, []);

    fs.readFileSync = originalReadFileSync;
    const currentRecords = readTaskLeases(root, { now });
    assert.equal(currentRecords.length, 1);
    assert.equal(currentRecords[0].event.event, 'ended');
  } finally {
    fs.readFileSync = originalReadFileSync;
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('asynchronous polling returns the same validated lease snapshot', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-lease-async-'));
  const now = 300_000;
  try {
    writeLease(root, {
      version: 1,
      provider: 'codex',
      event: 'running',
      sessionId: 'async-session',
      turnId: 'async-turn',
      timestamp: now,
      startedAt: now - 100,
    });
    const records = await readTaskLeasesAsync(root, { now });
    assert.equal(records.length, 1);
    assert.equal(records[0].event.sessionId, 'async-session');
    assert.equal(records[0].event.startedAt, now - 100);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('asynchronous polling discards an opened lease when the producer atomically replaces its path', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-lease-async-replace-'));
  const now = 350_000;
  const originalOpen = fs.promises.open;
  let replaced = false;
  try {
    const filePath = writeLease(root, {
      version: 1,
      provider: 'codex',
      event: 'running',
      sessionId: 'async-replaced-session',
      turnId: 'active-turn',
      timestamp: now - 100,
    });
    const replacementPath = `${filePath}.replacement`;

    fs.promises.open = async (...args) => {
      const handle = await originalOpen(...args);
      if (args[0] !== filePath) return handle;
      return {
        stat: handle.stat.bind(handle),
        chmod: handle.chmod.bind(handle),
        close: handle.close.bind(handle),
        readFile: async (...readArgs) => {
          const contents = await handle.readFile(...readArgs);
          if (!replaced) {
            fs.writeFileSync(replacementPath, JSON.stringify({
              version: 1,
              provider: 'codex',
              event: 'ended',
              sessionId: 'async-replaced-session',
              turnId: 'active-turn',
              timestamp: now,
            }), { mode: 0o600 });
            fs.renameSync(replacementPath, filePath);
            replaced = true;
          }
          return contents;
        },
      };
    };

    const racedRecords = await readTaskLeasesAsync(root, { now });
    assert.equal(replaced, true);
    assert.deepEqual(racedRecords, []);

    fs.promises.open = originalOpen;
    const currentRecords = await readTaskLeasesAsync(root, { now });
    assert.equal(currentRecords.length, 1);
    assert.equal(currentRecords[0].event.event, 'ended');
  } finally {
    fs.promises.open = originalOpen;
    fs.rmSync(root, { recursive: true, force: true });
  }
});
