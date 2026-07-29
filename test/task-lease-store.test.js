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

test('removes expired, oversized and malformed lease records', () => {
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
      assert.equal(fs.existsSync(filePath), false);
    }
  } finally {
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
