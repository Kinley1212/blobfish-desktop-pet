const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { EventEmitter } = require('events');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { execFileSync, spawn } = require('child_process');
const { AgentBridge, MAX_MESSAGE_BYTES } = require('../src/core/agent-bridge');
const { readTaskLeases } = require('../src/core/task-lease-store');

const senderPath = path.join(__dirname, '..', 'native', 'build', process.arch, 'blobfish-agent-event-sender');
if (process.platform === 'darwin') {
  execFileSync(process.execPath, [path.join(__dirname, '..', 'scripts', 'build-agent-sender.js'), process.arch]);
}

function runSender(socketPath, input, provider = 'codex') {
  return new Promise((resolve, reject) => {
    let stdout = '';
    const child = spawn(senderPath, ['--provider', provider], {
      env: {
        HOME: os.homedir(),
        PATH: '/usr/bin:/bin',
        BLOBFISH_SOCKET: socketPath,
      },
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stdin.end(JSON.stringify(input));
    child.on('error', reject);
    child.on('exit', (code) => code === 0 ? resolve(stdout) : reject(new Error(`sender exited ${code}`)));
  });
}

function runSenderWithTimeout(socketPath, input, timeoutMs, provider = 'codex') {
  return new Promise((resolve, reject) => {
    const child = spawn(senderPath, ['--provider', provider], {
      env: {
        HOME: os.homedir(),
        PATH: '/usr/bin:/bin',
        BLOBFISH_SOCKET: socketPath,
      },
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new Error(`sender exceeded ${timeoutMs}ms lock deadline`));
    }, timeoutMs);
    child.stdin.end(JSON.stringify(input));
    child.once('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.once('exit', (code, signal) => {
      clearTimeout(timer);
      if (code === 0) resolve();
      else reject(new Error(`sender exited ${code ?? signal}`));
    });
  });
}

function holdExclusiveFileLock(filePath) {
  const script = [
    'import fcntl, sys',
    'handle = open(sys.argv[1], "r+")',
    'fcntl.lockf(handle, fcntl.LOCK_EX)',
    'print("locked", flush=True)',
    'sys.stdin.read(1)',
  ].join('\n');
  const child = spawn('/usr/bin/python3', ['-c', script, filePath], {
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  let stderr = '';
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  return new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', (code) => {
      if (code !== 0) reject(new Error(`lock holder exited ${code}: ${stderr}`));
    });
    child.stdout.once('data', (chunk) => {
      if (!chunk.includes('locked')) {
        reject(new Error(`unexpected lock holder output: ${chunk}`));
        return;
      }
      resolve({
        release() {
          child.stdin.end();
          return new Promise((resolveExit, rejectExit) => {
            child.once('error', rejectExit);
            child.once('exit', (code) => code === 0
              ? resolveExit()
              : rejectExit(new Error(`lock holder exited ${code}: ${stderr}`)));
          });
        },
      });
    });
  });
}

function sessionDigest(provider, sessionId) {
  return crypto.createHash('sha256').update(`${provider}\0${sessionId}`).digest('hex');
}

function leasePathFor(directory, provider, sessionId) {
  return path.join(directory, `${sessionDigest(provider, sessionId)}.json`);
}

function writeLeaseFixture(directory, value, contents = JSON.stringify(value)) {
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  fs.chmodSync(directory, 0o700);
  const filePath = leasePathFor(directory, value.provider, value.sessionId);
  fs.writeFileSync(filePath, contents, { mode: 0o600 });
  return filePath;
}

function runPrune(leaseDirectory) {
  execFileSync(senderPath, ['--prune', '--lease-directory', leaseDirectory], {
    env: {
      HOME: os.homedir(),
      PATH: '/usr/bin:/bin',
    },
  });
}

function startSenderBehindInputBarrier(socketPath, input, provider = 'codex') {
  return new Promise((resolve, reject) => {
    let stdout = '';
    const child = spawn(senderPath, ['--provider', provider], {
      env: {
        HOME: os.homedir(),
        PATH: '/usr/bin:/bin',
        BLOBFISH_SOCKET: socketPath,
      },
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    const completion = new Promise((resolveExit, rejectExit) => {
      child.once('error', rejectExit);
      child.once('exit', (code) => code === 0
        ? resolveExit(stdout)
        : rejectExit(new Error(`sender exited ${code}`)));
    });
    child.once('error', reject);

    // A payload larger than the pipe buffer cannot finish flushing until the
    // sender is inside its bounded stdin read. Keeping stdin open then gives
    // the test a deterministic barrier before allowing the hook to proceed.
    child.stdin.write(' '.repeat(512 * 1024), (error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve({
        finish() {
          child.stdin.end(JSON.stringify(input));
          return completion;
        },
      });
    });
  });
}

test('accepts validated status-only events over a private Unix socket', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-bridge-'));
  const socketPath = path.join(directory, 'events.sock');
  const received = [];
  const errors = [];
  const bridge = new AgentBridge(socketPath, { onEvent: (event) => received.push(event), onError: (error) => errors.push(error) });
  try {
    await bridge.start();
    assert.equal(fs.statSync(socketPath).mode & 0o777, 0o600);
    await new Promise((resolve, reject) => {
      const socket = net.createConnection(socketPath, () => {
        socket.end(`${JSON.stringify({
          version: 1,
          provider: 'codex',
          event: 'started',
          sessionId: 'session-1',
          turnId: 'turn-1',
        })}\n`);
      });
      socket.on('close', resolve);
      socket.on('error', reject);
    });
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(received.length, 1);
    assert.equal(received[0].provider, 'codex');
    assert.equal(Object.prototype.hasOwnProperty.call(received[0], 'prompt'), false);
    assert.deepEqual(errors, []);
  } finally {
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('accepts one complete validated tail frame when the client ends without a newline', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-bridge-tail-'));
  const socketPath = path.join(directory, 'events.sock');
  const received = [];
  const errors = [];
  const bridge = new AgentBridge(socketPath, {
    onEvent: (event) => received.push(event),
    onError: (error) => errors.push(error),
  });
  try {
    await bridge.start();
    await new Promise((resolve, reject) => {
      const socket = net.createConnection(socketPath, () => {
        socket.end(JSON.stringify({
          version: 1,
          provider: 'codex',
          event: 'running',
          sessionId: 'tail-session',
          turnId: 'tail-turn',
        }));
      });
      socket.on('close', resolve);
      socket.on('error', reject);
    });
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(received.length, 1);
    assert.equal(received[0].sessionId, 'tail-session');
    assert.deepEqual(errors, []);
  } finally {
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('rejects an incomplete non-empty tail frame instead of treating it as an event', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-bridge-broken-tail-'));
  const socketPath = path.join(directory, 'events.sock');
  const received = [];
  const errors = [];
  const bridge = new AgentBridge(socketPath, {
    onEvent: (event) => received.push(event),
    onError: (error) => errors.push(error),
  });
  try {
    await bridge.start();
    await new Promise((resolve, reject) => {
      const socket = net.createConnection(socketPath, () => socket.end('{"version":1'));
      socket.on('close', resolve);
      socket.on('error', reject);
    });
    await new Promise((resolve) => setImmediate(resolve));
    assert.deepEqual(received, []);
    assert.equal(errors.length, 1);
    assert.match(errors[0].message, /Rejected local agent event/);
  } finally {
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('closes an idle local client after the configured connection deadline', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-bridge-idle-'));
  const socketPath = path.join(directory, 'events.sock');
  const bridge = new AgentBridge(socketPath, { connectionIdleTimeoutMs: 40 });
  let socket = null;
  try {
    await bridge.start();
    socket = await new Promise((resolve, reject) => {
      const client = net.createConnection(socketPath, () => resolve(client));
      client.once('error', reject);
    });
    socket.on('error', () => {});
    const closedPromptly = await Promise.race([
      new Promise((resolve) => socket.once('close', () => resolve(true))),
      new Promise((resolve) => setTimeout(() => resolve(false), 500)),
    ]);
    assert.equal(closedPromptly, true);
  } finally {
    socket?.destroy();
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('stop destroys half-open clients and resolves promptly', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-bridge-stop-'));
  const socketPath = path.join(directory, 'events.sock');
  const bridge = new AgentBridge(socketPath, { connectionIdleTimeoutMs: 60_000 });
  let socket = null;
  let stopPromise = null;
  try {
    await bridge.start();
    socket = await new Promise((resolve, reject) => {
      const client = net.createConnection(socketPath, () => resolve(client));
      client.once('error', reject);
    });
    socket.on('error', () => {});
    stopPromise = bridge.stop();
    const stoppedPromptly = await Promise.race([
      stopPromise.then(() => true),
      new Promise((resolve) => setTimeout(() => resolve(false), 500)),
    ]);
    assert.equal(stoppedPromptly, true);
  } finally {
    socket?.destroy();
    if (stopPromise) await stopPromise;
    else await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('bounds total bytes accepted from each connection even across newline-delimited frames', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-bridge-byte-limit-'));
  const socketPath = path.join(directory, 'events.sock');
  const received = [];
  const bridge = new AgentBridge(socketPath, { onEvent: (event) => received.push(event) });
  let socket = null;
  try {
    await bridge.start();
    socket = await new Promise((resolve, reject) => {
      const client = net.createConnection(socketPath, () => resolve(client));
      client.once('error', reject);
    });
    let closed = false;
    socket.on('error', () => {});
    socket.on('close', () => { closed = true; });
    const frames = Array.from({ length: 180 }, (_, index) => `${JSON.stringify({
      version: 1,
      provider: 'codex',
      event: 'running',
      sessionId: `byte-limit-session-${index}`,
      turnId: `byte-limit-turn-${index}`,
    })}\n`);
    assert.ok(Buffer.byteLength(frames.join('')) > MAX_MESSAGE_BYTES);
    for (const frame of frames) {
      if (closed) break;
      socket.write(frame);
      await new Promise((resolve) => setImmediate(resolve));
    }
    if (!closed) socket.end();
    if (!closed) {
      await Promise.race([
        new Promise((resolve) => socket.once('close', resolve)),
        new Promise((resolve) => setTimeout(resolve, 500)),
      ]);
    }
    assert.ok(received.length < frames.length);
  } finally {
    socket?.destroy();
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('handles client socket errors locally without surfacing bridge noise', () => {
  const errors = [];
  const bridge = new AgentBridge('/tmp/blobfish-unused.sock', {
    onError: (error) => errors.push(error),
  });
  const socket = new EventEmitter();
  socket.setEncoding = () => {};
  socket.setTimeout = () => {};
  socket.destroy = () => socket.emit('close');

  bridge.handleConnection(socket);
  assert.doesNotThrow(() => socket.emit('error', new Error('client reset')));
  assert.deepEqual(errors, []);
  socket.destroy();
});

test('rejects unsupported providers and oversized identifiers', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-bridge-invalid-'));
  const socketPath = path.join(directory, 'events.sock');
  const errors = [];
  const bridge = new AgentBridge(socketPath, { onError: (error) => errors.push(error) });
  try {
    await bridge.start();
    await new Promise((resolve) => {
      const socket = net.createConnection(socketPath, () => {
        socket.end(`${JSON.stringify({ version: 1, provider: 'unknown', event: 'started', sessionId: 'x' })}\n`);
      });
      socket.on('close', resolve);
    });
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(errors.length, 1);
    assert.match(errors[0].message, /provider/);
  } finally {
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native Codex hook sender forwards only whitelisted lifecycle metadata without Node', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-'));
  const socketPath = path.join(directory, 'events.sock');
  const received = [];
  const settingsPath = path.join(directory, 'settings.json');
  fs.writeFileSync(settingsPath, JSON.stringify({ privacy: { includeTaskTitles: true } }));
  const bridge = new AgentBridge(socketPath, { onEvent: (event) => received.push(event) });
  try {
    await bridge.start();
    const startOutput = await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: 'session-hook',
      turn_id: 'turn-hook',
      prompt: '整理发布说明',
      transcript_path: '/private/transcript.jsonl',
    });
    const stopOutput = await runSender(socketPath, {
      hook_event_name: 'Stop',
      session_id: 'session-hook',
      turn_id: 'turn-hook',
      success: true,
      status: 'completed',
    });
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(received.length, 2);
    for (const event of received) {
      assert.deepEqual(
        Object.keys(event).sort(),
        ['event', 'provider', 'sessionId', 'timestamp', 'title', 'turnId', 'version'].sort(),
      );
    }
    assert.deepEqual(received.map((event) => event.event), ['started', 'ended']);
    assert.equal(received[0].title, '整理发布说明');
    assert.equal(received[1].title, null);
    assert.equal(startOutput, '');
    assert.deepEqual(JSON.parse(stopOutput), {});
  } finally {
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native Codex hook sender keeps titles private unless the user opts in', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-private-'));
  const socketPath = path.join(directory, 'events.sock');
  const received = [];
  const bridge = new AgentBridge(socketPath, { onEvent: (event) => received.push(event) });
  try {
    await bridge.start();
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: 'private-session',
      prompt: 'keep this private',
    });
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(received.length, 1);
    assert.equal(received[0].title, null);
  } finally {
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native hook sender writes a private atomic lease while the pet is offline', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-lease-'));
  const socketPath = path.join(directory, 'missing.sock');
  const leaseDirectory = path.join(directory, 'agent-task-leases');
  try {
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: 'offline-session',
      turn_id: 'offline-turn',
      prompt: 'this title stays private',
      transcript_path: '/private/transcript.jsonl',
    });

    assert.equal(fs.statSync(leaseDirectory).mode & 0o777, 0o700);
    const files = fs.readdirSync(leaseDirectory).filter((name) => name.endsWith('.json'));
    assert.equal(files.length, 1);
    assert.match(files[0], /^[a-f0-9]{64}\.json$/);
    assert.equal(files[0].includes('offline-session'), false);
    const filePath = path.join(leaseDirectory, files[0]);
    assert.equal(fs.statSync(filePath).mode & 0o777, 0o600);

    const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    assert.equal(raw.event, 'started');
    assert.equal(raw.sessionId, 'offline-session');
    assert.equal(raw.turnId, 'offline-turn');
    assert.equal(raw.startedAt, raw.timestamp);
    assert.equal(Object.prototype.hasOwnProperty.call(raw, 'title'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(raw, 'prompt'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(raw, 'transcript_path'), false);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native hook sender preserves an active snapshot and leaves a short terminal tombstone', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-tombstone-'));
  const socketPath = path.join(directory, 'missing.sock');
  const settingsPath = path.join(directory, 'settings.json');
  const leaseDirectory = path.join(directory, 'agent-task-leases');
  fs.writeFileSync(settingsPath, JSON.stringify({ privacy: { includeTaskTitles: true } }));
  try {
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: 'recover-session',
      turn_id: 'recover-turn',
      prompt: '恢复正在运行的任务',
    });
    await runSender(socketPath, {
      hook_event_name: 'PostToolUse',
      session_id: 'recover-session',
      turn_id: 'recover-turn',
    });

    let records = readTaskLeases(leaseDirectory);
    assert.equal(records.length, 1);
    assert.equal(records[0].event.event, 'running');
    assert.equal(records[0].event.title, '恢复正在运行的任务');
    assert.ok(records[0].event.startedAt <= records[0].event.timestamp);

    await runSender(socketPath, {
      hook_event_name: 'SessionEnd',
      session_id: 'recover-session',
      turn_id: 'recover-turn',
    });
    records = readTaskLeases(leaseDirectory);
    assert.equal(records.length, 1);
    assert.equal(records[0].event.event, 'ended');
    assert.equal(records[0].event.title, null);
    const terminalRaw = JSON.parse(fs.readFileSync(records[0].filePath, 'utf8'));
    assert.equal(Object.prototype.hasOwnProperty.call(terminalRaw, 'title'), false);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native Claude hook sender uses the official prompt_id as the turn generation', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-turn-'));
  const socketPath = path.join(directory, 'events.sock');
  const received = [];
  const bridge = new AgentBridge(socketPath, { onEvent: (event) => received.push(event) });
  try {
    await bridge.start();
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: 'claude-turn-session',
      prompt_id: '11111111-1111-4111-8111-111111111111',
      prompt: '第一件事',
    }, 'claude-code');
    await runSender(socketPath, {
      hook_event_name: 'PostToolUse',
      session_id: 'claude-turn-session',
      prompt_id: '11111111-1111-4111-8111-111111111111',
    }, 'claude-code');
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: 'claude-turn-session',
      prompt_id: '22222222-2222-4222-8222-222222222222',
      prompt: '第二件事',
    }, 'claude-code');
    await new Promise((resolve) => setImmediate(resolve));

    assert.equal(received.length, 3);
    assert.equal(received[0].turnId, '11111111-1111-4111-8111-111111111111');
    assert.equal(received[1].turnId, received[0].turnId);
    assert.equal(received[2].turnId, '22222222-2222-4222-8222-222222222222');
  } finally {
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('legacy Claude hooks without prompt_id never guess which synthetic turn to finish', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-legacy-turn-'));
  const socketPath = path.join(directory, 'events.sock');
  const leaseDirectory = path.join(directory, 'agent-task-leases');
  const received = [];
  const bridge = new AgentBridge(socketPath, { onEvent: (event) => received.push(event) });
  try {
    await bridge.start();
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: 'legacy-claude-session',
      prompt: '旧版 Claude 任务',
    }, 'claude-code');
    await runSender(socketPath, {
      hook_event_name: 'PostToolUse',
      session_id: 'legacy-claude-session',
    }, 'claude-code');
    await runSender(socketPath, {
      hook_event_name: 'Stop',
      session_id: 'legacy-claude-session',
    }, 'claude-code');
    await new Promise((resolve) => setImmediate(resolve));

    assert.equal(received.length, 1);
    assert.equal(received[0].event, 'started');
    assert.match(received[0].turnId, /^blobfish-[a-f0-9-]+$/);
    const records = readTaskLeases(leaseDirectory);
    assert.equal(records.length, 1);
    assert.equal(records[0].event.event, 'started');
    assert.equal(records[0].event.turnId, received[0].turnId);
  } finally {
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('late Claude events from an old prompt cannot overwrite a newer started generation', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-generation-race-'));
  const socketPath = path.join(directory, 'missing.sock');
  const leaseDirectory = path.join(directory, 'agent-task-leases');
  const sessionId = 'claude-generation-race';
  const oldPromptId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const newPromptId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  try {
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: sessionId,
      prompt_id: oldPromptId,
      prompt: '旧任务',
    }, 'claude-code');

    const delayedRunning = await startSenderBehindInputBarrier(socketPath, {
      hook_event_name: 'PostToolUse',
      session_id: sessionId,
      prompt_id: oldPromptId,
    }, 'claude-code');
    const delayedTerminal = await startSenderBehindInputBarrier(socketPath, {
      hook_event_name: 'Stop',
      session_id: sessionId,
      prompt_id: oldPromptId,
    }, 'claude-code');

    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: sessionId,
      prompt_id: newPromptId,
      prompt: '新任务',
    }, 'claude-code');
    await delayedRunning.finish();
    await delayedTerminal.finish();

    const records = readTaskLeases(leaseDirectory);
    assert.equal(records.length, 1);
    assert.equal(records[0].event.event, 'started');
    assert.equal(records[0].event.turnId, newPromptId);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('a mismatched stale turn is rejected instead of using socket-only fallback', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-stale-delivery-'));
  const socketPath = path.join(directory, 'events.sock');
  const received = [];
  const bridge = new AgentBridge(socketPath, { onEvent: (event) => received.push(event) });
  try {
    await bridge.start();
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: 'stale-delivery-session',
      prompt_id: '56565656-5656-4656-8656-565656565656',
      prompt: '当前任务',
    }, 'claude-code');
    await runSender(socketPath, {
      hook_event_name: 'Stop',
      session_id: 'stale-delivery-session',
      prompt_id: '78787878-7878-4878-8878-787878787878',
    }, 'claude-code');
    await new Promise((resolve) => setImmediate(resolve));

    assert.equal(received.length, 1);
    assert.equal(received[0].event, 'started');
    assert.equal(received[0].turnId, '56565656-5656-4656-8656-565656565656');
  } finally {
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('a delayed older start cannot replace a newer committed generation', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-start-race-'));
  const socketPath = path.join(directory, 'missing.sock');
  const leaseDirectory = path.join(directory, 'agent-task-leases');
  const sessionId = 'claude-start-race';
  const oldPromptId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  const newPromptId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  try {
    const delayedStart = await startSenderBehindInputBarrier(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: sessionId,
      prompt_id: oldPromptId,
      prompt: '旧任务',
    }, 'claude-code');
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: sessionId,
      prompt_id: newPromptId,
      prompt: '新任务',
    }, 'claude-code');
    await delayedStart.finish();

    const records = readTaskLeases(leaseDirectory);
    assert.equal(records.length, 1);
    assert.equal(records[0].event.event, 'started');
    assert.equal(records[0].event.turnId, newPromptId);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('a delayed start cannot resurrect its turn after the terminal event committed first', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-terminal-race-'));
  const socketPath = path.join(directory, 'missing.sock');
  const leaseDirectory = path.join(directory, 'agent-task-leases');
  const sessionId = 'claude-terminal-race';
  const promptId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  try {
    const delayedStart = await startSenderBehindInputBarrier(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: sessionId,
      prompt_id: promptId,
      prompt: '不能复活的任务',
    }, 'claude-code');
    await runSender(socketPath, {
      hook_event_name: 'Stop',
      session_id: sessionId,
      prompt_id: promptId,
    }, 'claude-code');
    await delayedStart.finish();

    const records = readTaskLeases(leaseDirectory);
    assert.equal(records.length, 1);
    assert.equal(records[0].event.event, 'ended');
    assert.equal(records[0].event.turnId, promptId);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('a started lease from another boot falls back to wall time instead of stale monotonic time', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-cross-boot-'));
  const socketPath = path.join(directory, 'missing.sock');
  const leaseDirectory = path.join(directory, 'agent-task-leases');
  const sessionId = 'cross-boot-session';
  const oldPromptId = '12121212-1212-4212-8212-121212121212';
  const newPromptId = '34343434-3434-4434-8434-343434343434';
  const oldTimestamp = Date.now() - 1_000;
  try {
    writeLeaseFixture(leaseDirectory, {
      version: 1,
      provider: 'claude-code',
      event: 'started',
      sessionId,
      turnId: oldPromptId,
      timestamp: oldTimestamp,
      startedAt: oldTimestamp,
      _generationStartedAtNs: Number.MAX_SAFE_INTEGER,
      _generationBootTimeSeconds: 1,
    });

    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: sessionId,
      prompt_id: newPromptId,
      prompt: '重启后的新任务',
    }, 'claude-code');

    const records = readTaskLeases(leaseDirectory);
    assert.equal(records.length, 1);
    assert.equal(records[0].event.event, 'started');
    assert.equal(records[0].event.turnId, newPromptId);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('concurrent native senders leave one complete atomic lease instead of deleting a newer turn', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-concurrent-'));
  const socketPath = path.join(directory, 'missing.sock');
  const leaseDirectory = path.join(directory, 'agent-task-leases');
  try {
    await Promise.all(Array.from({ length: 6 }, (_, index) => runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: 'shared-session',
      prompt: `任务 ${index}`,
    }, 'claude-code')));

    const records = readTaskLeases(leaseDirectory);
    assert.equal(records.length, 1);
    assert.equal(records[0].event.event, 'started');
    assert.equal(records[0].event.sessionId, 'shared-session');
    assert.match(records[0].event.turnId, /^blobfish-[a-f0-9-]+$/);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('a new start safely replaces a corrupt private lease snapshot', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-corrupt-lease-'));
  const socketPath = path.join(directory, 'missing.sock');
  const leaseDirectory = path.join(directory, 'agent-task-leases');
  const sessionId = 'corrupt-lease-session';
  const digest = sessionDigest('codex', sessionId);
  fs.mkdirSync(leaseDirectory, { mode: 0o700 });
  fs.writeFileSync(path.join(leaseDirectory, `${digest}.json`), '{broken', { mode: 0o600 });
  try {
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: sessionId,
      turn_id: 'replacement-turn',
    });
    const records = readTaskLeases(leaseDirectory);
    assert.equal(records.length, 1);
    assert.equal(records[0].event.event, 'started');
    assert.equal(records[0].event.turnId, 'replacement-turn');
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native sender rejects a non-private lease directory instead of repairing and trusting it', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-public-dir-'));
  const socketPath = path.join(directory, 'events.sock');
  const leaseDirectory = path.join(directory, 'agent-task-leases');
  const received = [];
  const bridge = new AgentBridge(socketPath, { onEvent: (event) => received.push(event) });
  fs.mkdirSync(leaseDirectory, { mode: 0o755 });
  fs.chmodSync(leaseDirectory, 0o755);
  try {
    await bridge.start();
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: 'public-directory-session',
      turn_id: 'public-directory-turn',
    });
    assert.equal(fs.statSync(leaseDirectory).mode & 0o777, 0o755);
    assert.deepEqual(fs.readdirSync(leaseDirectory), []);
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(received.length, 1);
    assert.equal(received[0].turnId, 'public-directory-turn');
  } finally {
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native sender rejects pre-positioned lock and lease symlinks', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-symlink-'));
  const socketPath = path.join(directory, 'events.sock');
  const leaseDirectory = path.join(directory, 'agent-task-leases');
  const received = [];
  const bridge = new AgentBridge(socketPath, { onEvent: (event) => received.push(event) });
  fs.mkdirSync(leaseDirectory, { mode: 0o700 });
  const victimPath = path.join(directory, 'victim.txt');
  fs.writeFileSync(victimPath, 'do not touch', { mode: 0o600 });

  const lockSession = 'lock-symlink-session';
  const lockDigest = sessionDigest('codex', lockSession);
  const lockPath = path.join(leaseDirectory, `${lockDigest}.lock`);
  fs.symlinkSync(victimPath, lockPath);
  try {
    await bridge.start();
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: lockSession,
      turn_id: 'lock-symlink-turn',
    });
    assert.equal(fs.lstatSync(lockPath).isSymbolicLink(), true);
    assert.equal(fs.readFileSync(victimPath, 'utf8'), 'do not touch');
    assert.equal(fs.existsSync(path.join(leaseDirectory, `${lockDigest}.json`)), false);

    fs.unlinkSync(lockPath);
    const leaseSession = 'lease-symlink-session';
    const leaseDigest = sessionDigest('codex', leaseSession);
    const leasePath = path.join(leaseDirectory, `${leaseDigest}.json`);
    fs.symlinkSync(victimPath, leasePath);
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: leaseSession,
      turn_id: 'lease-symlink-turn',
    });
    assert.equal(fs.lstatSync(leasePath).isSymbolicLink(), true);
    assert.equal(fs.readFileSync(victimPath, 'utf8'), 'do not touch');
    await new Promise((resolve) => setImmediate(resolve));
    assert.deepEqual(
      received.map((event) => event.sessionId),
      [lockSession, leaseSession],
    );
  } finally {
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native sender exits promptly instead of blocking on a held session lock', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-lock-timeout-'));
  const socketPath = path.join(directory, 'events.sock');
  const leaseDirectory = path.join(directory, 'agent-task-leases');
  const sessionId = 'held-lock-session';
  const digest = sessionDigest('codex', sessionId);
  const lockPath = path.join(leaseDirectory, `${digest}.lock`);
  const received = [];
  const bridge = new AgentBridge(socketPath, { onEvent: (event) => received.push(event) });
  fs.mkdirSync(leaseDirectory, { mode: 0o700 });
  fs.writeFileSync(lockPath, '', { mode: 0o600 });
  const holder = await holdExclusiveFileLock(lockPath);
  try {
    await bridge.start();
    await runSenderWithTimeout(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: sessionId,
      turn_id: 'held-lock-turn',
    }, 500);
    assert.equal(fs.existsSync(path.join(leaseDirectory, `${digest}.json`)), false);
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(received.length, 1);
    assert.equal(received[0].turnId, 'held-lock-turn');
  } finally {
    await bridge.stop();
    await holder.release();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native prune removes expired or corrupt leases and keeps fresh or symlink entries', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-prune-'));
  const leaseDirectory = path.join(directory, 'agent-task-leases');
  const now = Date.now();
  try {
    const expiredRunning = writeLeaseFixture(leaseDirectory, {
      version: 1,
      provider: 'codex',
      event: 'running',
      sessionId: 'expired-running',
      turnId: 'expired-running-turn',
      timestamp: now - (30 * 60 * 1000) - 1_000,
    });
    const expiredStarted = writeLeaseFixture(leaseDirectory, {
      version: 1,
      provider: 'codex',
      event: 'started',
      sessionId: 'expired-started',
      turnId: 'expired-started-turn',
      timestamp: now - (15 * 60 * 1000) - 1_000,
    });
    const expiredWaiting = writeLeaseFixture(leaseDirectory, {
      version: 1,
      provider: 'claude-code',
      event: 'needs_input',
      sessionId: 'expired-waiting',
      turnId: 'expired-waiting-turn',
      timestamp: now - (8 * 60 * 60 * 1000) - 1_000,
    });
    const expiredTerminal = writeLeaseFixture(leaseDirectory, {
      version: 1,
      provider: 'codex',
      event: 'ended',
      sessionId: 'expired-terminal',
      turnId: 'expired-terminal-turn',
      timestamp: now - (5 * 60 * 1000) - 1_000,
    });
    const malformed = writeLeaseFixture(leaseDirectory, {
      provider: 'codex',
      sessionId: 'malformed-lease',
    }, '{broken');
    const fresh = writeLeaseFixture(leaseDirectory, {
      version: 1,
      provider: 'codex',
      event: 'started',
      sessionId: 'fresh-running',
      turnId: 'fresh-running-turn',
      timestamp: now,
    });
    const freshRunning = writeLeaseFixture(leaseDirectory, {
      version: 1,
      provider: 'codex',
      event: 'running',
      sessionId: 'fresh-running-heartbeat',
      turnId: 'fresh-running-heartbeat-turn',
      timestamp: now - (20 * 60 * 1000),
    });
    const victimPath = path.join(directory, 'victim.txt');
    fs.writeFileSync(victimPath, 'keep me', { mode: 0o600 });
    const symlinkPath = leasePathFor(leaseDirectory, 'codex', 'symlink-lease');
    fs.symlinkSync(victimPath, symlinkPath);

    runPrune(leaseDirectory);

    for (const removed of [expiredRunning, expiredStarted, expiredWaiting, expiredTerminal, malformed]) {
      assert.equal(fs.existsSync(removed), false);
    }
    assert.equal(fs.existsSync(fresh), true);
    assert.equal(fs.existsSync(freshRunning), true);
    assert.equal(fs.lstatSync(symlinkPath).isSymbolicLink(), true);
    assert.equal(fs.readFileSync(victimPath, 'utf8'), 'keep me');
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native prune skips a busy session and deletes it only after the lock is released', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-prune-lock-'));
  const leaseDirectory = path.join(directory, 'agent-task-leases');
  const sessionId = 'busy-expired-session';
  const leasePath = writeLeaseFixture(leaseDirectory, {
    version: 1,
    provider: 'codex',
    event: 'ended',
    sessionId,
    turnId: 'busy-expired-turn',
    timestamp: Date.now() - (5 * 60 * 1000) - 1_000,
  });
  const lockPath = path.join(leaseDirectory, `${sessionDigest('codex', sessionId)}.lock`);
  fs.writeFileSync(lockPath, '', { mode: 0o600 });
  const holder = await holdExclusiveFileLock(lockPath);
  let released = false;
  try {
    runPrune(leaseDirectory);
    assert.equal(fs.existsSync(leasePath), true);
    await holder.release();
    released = true;
    runPrune(leaseDirectory);
    assert.equal(fs.existsSync(leasePath), false);
  } finally {
    if (!released) await holder.release();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native hook sender extracts the written request instead of attachment metadata', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-attachment-'));
  const socketPath = path.join(directory, 'events.sock');
  const settingsPath = path.join(directory, 'settings.json');
  const received = [];
  fs.writeFileSync(settingsPath, JSON.stringify({ privacy: { includeTaskTitles: true } }));
  const bridge = new AgentBridge(socketPath, { onEvent: (event) => received.push(event) });
  try {
    await bridge.start();
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: 'attachment-session',
      turn_id: 'attachment-turn',
      prompt: [
        '# Files mentioned by the user:',
        '',
        '## codex-clipboard-f288998d.png: /private/tmp/codex-clipboard-f288998d.png',
        '',
        '## My request for Codex:',
        '',
        '把设置里的错位修好',
        '<image name="Image #1" path="/private/tmp/codex-clipboard-f288998d.png"></image>',
      ].join('\n'),
    });
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(received[0].title, '把设置里的错位修好');
  } finally {
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native hook sender uses a readable fallback for attachment-only prompts and opaque identifiers', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-fallback-'));
  const socketPath = path.join(directory, 'events.sock');
  const settingsPath = path.join(directory, 'settings.json');
  const received = [];
  fs.writeFileSync(settingsPath, JSON.stringify({ privacy: { includeTaskTitles: true } }));
  const bridge = new AgentBridge(socketPath, { onEvent: (event) => received.push(event) });
  try {
    await bridge.start();
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: 'attachment-only',
      prompt: '# Files mentioned by the user:\n## photo.png: /private/tmp/photo.png\n<image path="/private/tmp/photo.png"></image>',
    });
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: 'opaque-only',
      prompt: 'f288998d-b48f-45d5-8f91-4a42fc6db7ef',
    });
    await new Promise((resolve) => setImmediate(resolve));
    assert.deepEqual(received.map((event) => event.title), ['Codex 附件任务', 'Codex 任务']);
  } finally {
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native Claude hook sender keeps active background work and handles approval or session events', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-claude-'));
  const socketPath = path.join(directory, 'events.sock');
  const received = [];
  const bridge = new AgentBridge(socketPath, { onEvent: (event) => received.push(event) });
  try {
    await bridge.start();
    await runSender(socketPath, {
      hook_event_name: 'Stop',
      session_id: 'claude-background',
      prompt_id: '33333333-3333-4333-8333-333333333333',
      background_tasks: [{ id: 'task-1', status: 'running' }],
      session_crons: [],
    }, 'claude-code');
    await runSender(socketPath, {
      hook_event_name: 'Notification',
      notification_type: 'agent_needs_input',
      session_id: 'claude-waiting',
    }, 'claude-code');
    await runSender(socketPath, {
      hook_event_name: 'Notification',
      notification_type: 'permission_prompt',
      session_id: 'claude-permission',
    }, 'claude-code');
    await runSender(socketPath, {
      hook_event_name: 'Notification',
      notification_type: 'elicitation_dialog',
      session_id: 'claude-elicitation',
    }, 'claude-code');
    await runSender(socketPath, {
      hook_event_name: 'Notification',
      notification_type: 'idle_prompt',
      session_id: 'claude-idle',
    }, 'claude-code');
    await runSender(socketPath, {
      hook_event_name: 'SessionEnd',
      session_id: 'claude-ended',
    }, 'claude-code');
    await new Promise((resolve) => setImmediate(resolve));
    assert.deepEqual(
      received.map((event) => [event.sessionId, event.event]),
      [
        ['claude-background', 'running'],
        ['claude-waiting', 'needs_input'],
        ['claude-permission', 'needs_input'],
        ['claude-elicitation', 'needs_input'],
        ['claude-ended', 'ended'],
      ],
    );
  } finally {
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
