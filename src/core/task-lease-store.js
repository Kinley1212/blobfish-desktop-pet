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

async function removeLeaseAsync(filePath) {
  try {
    await fs.promises.unlink(filePath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

function isMissingOrSymlinkRace(error) {
  return error.code === 'ENOENT' || error.code === 'ELOOP';
}

function leaseNames(names) {
  return names.filter((name) => /^[a-f0-9]{64}\.json$/.test(name));
}

function sortNewestFirst(left, right) {
  return right.mtimeMs - left.mtimeMs || left.name.localeCompare(right.name);
}

function listRecentLeaseFiles(directory) {
  const files = [];
  for (const name of leaseNames(fs.readdirSync(directory))) {
    const filePath = path.join(directory, name);
    try {
      const stat = fs.lstatSync(filePath);
      if (stat.isFile() && !stat.isSymbolicLink()) {
        files.push({ filePath, mtimeMs: stat.mtimeMs, name });
      }
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
  return files.sort(sortNewestFirst);
}

async function listRecentLeaseFilesAsync(directory) {
  const files = [];
  for (const name of leaseNames(await fs.promises.readdir(directory))) {
    const filePath = path.join(directory, name);
    try {
      const stat = await fs.promises.lstat(filePath);
      if (stat.isFile() && !stat.isSymbolicLink()) {
        files.push({ filePath, mtimeMs: stat.mtimeMs, name });
      }
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
  return files.sort(sortNewestFirst);
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

function parseLease(contents, filePath, options) {
  try {
    return normalizeLease(JSON.parse(contents), filePath, options);
  } catch {
    return null;
  }
}

function hasSameFileIdentity(left, right) {
  return left.dev === right.dev
    && left.ino === right.ino
    && left.size === right.size
    && left.mtimeMs === right.mtimeMs;
}

function readLeaseFile(filePath, options) {
  let descriptor;
  try {
    const noFollow = fs.constants.O_NOFOLLOW || 0;
    descriptor = fs.openSync(filePath, fs.constants.O_RDONLY | noFollow);
  } catch (error) {
    if (isMissingOrSymlinkRace(error)) return null;
    throw error;
  }

  try {
    const openedStat = fs.fstatSync(descriptor);
    if (!openedStat.isFile() || openedStat.size > MAX_LEASE_BYTES) return null;
    fs.fchmodSync(descriptor, 0o600);
    const record = parseLease(fs.readFileSync(descriptor, 'utf8'), filePath, options);
    if (!record) return null;

    const finalDescriptorStat = fs.fstatSync(descriptor);
    let currentPathStat;
    try {
      currentPathStat = fs.lstatSync(filePath);
    } catch (error) {
      if (isMissingOrSymlinkRace(error)) return null;
      throw error;
    }
    if (!finalDescriptorStat.isFile()
      || !currentPathStat.isFile()
      || currentPathStat.isSymbolicLink()
      || !hasSameFileIdentity(openedStat, finalDescriptorStat)
      || !hasSameFileIdentity(finalDescriptorStat, currentPathStat)) {
      return null;
    }
    return record;
  } finally {
    fs.closeSync(descriptor);
  }
}

async function readLeaseFileAsync(filePath, options) {
  let file;
  try {
    const noFollow = fs.constants.O_NOFOLLOW || 0;
    file = await fs.promises.open(filePath, fs.constants.O_RDONLY | noFollow);
  } catch (error) {
    if (isMissingOrSymlinkRace(error)) return null;
    throw error;
  }

  try {
    const openedStat = await file.stat();
    if (!openedStat.isFile() || openedStat.size > MAX_LEASE_BYTES) return null;
    await file.chmod(0o600);
    const record = parseLease(await file.readFile({ encoding: 'utf8' }), filePath, options);
    if (!record) return null;

    const finalDescriptorStat = await file.stat();
    let currentPathStat;
    try {
      currentPathStat = await fs.promises.lstat(filePath);
    } catch (error) {
      if (isMissingOrSymlinkRace(error)) return null;
      throw error;
    }
    if (!finalDescriptorStat.isFile()
      || !currentPathStat.isFile()
      || currentPathStat.isSymbolicLink()
      || !hasSameFileIdentity(openedStat, finalDescriptorStat)
      || !hasSameFileIdentity(finalDescriptorStat, currentPathStat)) {
      return null;
    }
    return record;
  } finally {
    await file.close();
  }
}

function readTaskLeases(directory, options = {}) {
  const now = options.now ?? Date.now();
  const activeMaxAgeMs = options.activeMaxAgeMs ?? ACTIVE_LEASE_MAX_AGE_MS;
  const waitingMaxAgeMs = options.waitingMaxAgeMs ?? WAITING_LEASE_MAX_AGE_MS;
  const terminalMaxAgeMs = options.terminalMaxAgeMs ?? TERMINAL_LEASE_MAX_AGE_MS;
  let directoryStat;
  try {
    directoryStat = fs.lstatSync(directory);
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
  if (!directoryStat.isDirectory() || directoryStat.isSymbolicLink()) {
    throw new Error('Task lease path is not a private directory');
  }
  fs.chmodSync(directory, 0o700);

  const records = [];
  const normalizeOptions = {
    now,
    activeMaxAgeMs,
    waitingMaxAgeMs,
    terminalMaxAgeMs,
  };
  for (const { filePath } of listRecentLeaseFiles(directory)) {
    const record = readLeaseFile(filePath, normalizeOptions);
    if (record) records.push(record);
    if (records.length >= MAX_LEASE_FILES) break;
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

  const records = [];
  const normalizeOptions = {
    now,
    activeMaxAgeMs,
    waitingMaxAgeMs,
    terminalMaxAgeMs,
  };
  for (const { filePath } of await listRecentLeaseFilesAsync(directory)) {
    const record = await readLeaseFileAsync(filePath, normalizeOptions);
    if (record) records.push(record);
    if (records.length >= MAX_LEASE_FILES) break;
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
