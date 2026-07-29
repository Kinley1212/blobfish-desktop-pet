const fs = require('fs');
const path = require('path');
const { validateAgentEvent } = require('./agent-event-schema');

const ACTIVE_LEASE_MAX_AGE_MS = 2 * 60 * 60 * 1000;
const WAITING_LEASE_MAX_AGE_MS = 8 * 60 * 60 * 1000;
const TERMINAL_LEASE_MAX_AGE_MS = 5 * 60 * 1000;
const MAX_LEASE_BYTES = 16 * 1024;
const MAX_LEASE_FILES = 256;
const MAX_FUTURE_SKEW_MS = 60 * 1000;
const ACTIVE_EVENTS = new Set(['started', 'running', 'needs_input']);
const TERMINAL_EVENTS = new Set(['ended', 'completed', 'failed']);

function removeLease(filePath) {
  try {
    fs.unlinkSync(filePath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

function sameFile(left, right) {
  return left.dev === right.dev
    && left.ino === right.ino
    && left.size === right.size
    && left.mtimeMs === right.mtimeMs;
}

function removeLeaseIfUnchanged(filePath, expectedStat) {
  try {
    const currentStat = fs.lstatSync(filePath);
    if (sameFile(currentStat, expectedStat)) removeLease(filePath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

async function removeLeaseAsync(filePath) {
  try {
    await fs.promises.unlink(filePath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

async function removeLeaseIfUnchangedAsync(filePath, expectedStat) {
  try {
    const currentStat = await fs.promises.lstat(filePath);
    if (sameFile(currentStat, expectedStat)) await removeLeaseAsync(filePath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

function leaseNames(names) {
  return names
    .filter((name) => /^[a-f0-9]{64}\.json$/.test(name))
    .sort()
    .slice(0, MAX_LEASE_FILES);
}

function normalizeLease(raw, filePath, options) {
  const { now, activeMaxAgeMs, waitingMaxAgeMs, terminalMaxAgeMs } = options;
  const event = validateAgentEvent(raw);
  if (!ACTIVE_EVENTS.has(event.event) && !TERMINAL_EVENTS.has(event.event)) {
    throw new Error('Task lease event is not recoverable');
  }
  if (event.timestamp > now + MAX_FUTURE_SKEW_MS) {
    throw new Error('Task lease timestamp is in the future');
  }
  const maxAgeMs = TERMINAL_EVENTS.has(event.event)
    ? terminalMaxAgeMs
    : event.event === 'needs_input'
      ? waitingMaxAgeMs
      : activeMaxAgeMs;
  if (now - event.timestamp > maxAgeMs) throw new Error('Task lease has expired');

  const startedAt = Number.isFinite(raw.startedAt)
    && raw.startedAt >= 0
    && raw.startedAt <= event.timestamp
    ? raw.startedAt
    : event.timestamp;
  return Object.freeze({
    filePath,
    event: Object.freeze({
      ...event,
      timestamp: Math.min(event.timestamp, now),
      startedAt: Math.min(startedAt, now),
      recovered: true,
    }),
  });
}

function readTaskLeases(directory, options = {}) {
  const now = options.now ?? Date.now();
  const activeMaxAgeMs = options.activeMaxAgeMs ?? ACTIVE_LEASE_MAX_AGE_MS;
  const waitingMaxAgeMs = options.waitingMaxAgeMs ?? WAITING_LEASE_MAX_AGE_MS;
  const terminalMaxAgeMs = options.terminalMaxAgeMs ?? TERMINAL_LEASE_MAX_AGE_MS;
  if (!fs.existsSync(directory)) return [];

  const directoryStat = fs.lstatSync(directory);
  if (!directoryStat.isDirectory() || directoryStat.isSymbolicLink()) {
    throw new Error('Task lease path is not a private directory');
  }
  fs.chmodSync(directory, 0o700);

  const names = leaseNames(fs.readdirSync(directory));
  const records = [];

  for (const name of names) {
    const filePath = path.join(directory, name);
    let stat = null;
    try {
      stat = fs.lstatSync(filePath);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size > MAX_LEASE_BYTES) {
        removeLeaseIfUnchanged(filePath, stat);
        continue;
      }
      fs.chmodSync(filePath, 0o600);
      const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      records.push(normalizeLease(raw, filePath, {
        now,
        activeMaxAgeMs,
        waitingMaxAgeMs,
        terminalMaxAgeMs,
      }));
    } catch {
      if (stat) removeLeaseIfUnchanged(filePath, stat);
    }
  }

  return records.sort((left, right) => left.event.timestamp - right.event.timestamp);
}

async function readTaskLeasesAsync(directory, options = {}) {
  const now = options.now ?? Date.now();
  const activeMaxAgeMs = options.activeMaxAgeMs ?? ACTIVE_LEASE_MAX_AGE_MS;
  const waitingMaxAgeMs = options.waitingMaxAgeMs ?? WAITING_LEASE_MAX_AGE_MS;
  const terminalMaxAgeMs = options.terminalMaxAgeMs ?? TERMINAL_LEASE_MAX_AGE_MS;
  let directoryStat;
  try {
    directoryStat = await fs.promises.lstat(directory);
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
  if (!directoryStat.isDirectory() || directoryStat.isSymbolicLink()) {
    throw new Error('Task lease path is not a private directory');
  }
  await fs.promises.chmod(directory, 0o700);

  const names = leaseNames(await fs.promises.readdir(directory));
  const records = [];
  for (const name of names) {
    const filePath = path.join(directory, name);
    let stat = null;
    try {
      stat = await fs.promises.lstat(filePath);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size > MAX_LEASE_BYTES) {
        await removeLeaseIfUnchangedAsync(filePath, stat);
        continue;
      }
      await fs.promises.chmod(filePath, 0o600);
      const raw = JSON.parse(await fs.promises.readFile(filePath, 'utf8'));
      records.push(normalizeLease(raw, filePath, {
        now,
        activeMaxAgeMs,
        waitingMaxAgeMs,
        terminalMaxAgeMs,
      }));
    } catch {
      if (stat) await removeLeaseIfUnchangedAsync(filePath, stat);
    }
  }
  return records.sort((left, right) => left.event.timestamp - right.event.timestamp);
}

function readActiveTaskLeases(directory, options = {}) {
  return readTaskLeases(directory, options)
    .map((record) => record.event)
    .filter((event) => ACTIVE_EVENTS.has(event.event));
}

module.exports = {
  ACTIVE_LEASE_MAX_AGE_MS,
  MAX_LEASE_BYTES,
  MAX_LEASE_FILES,
  TERMINAL_LEASE_MAX_AGE_MS,
  WAITING_LEASE_MAX_AGE_MS,
  readActiveTaskLeases,
  readTaskLeases,
  readTaskLeasesAsync,
  removeLease,
  removeLeaseAsync,
};
