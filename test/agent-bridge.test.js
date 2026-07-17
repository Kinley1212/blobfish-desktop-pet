const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { execFileSync, spawn } = require('child_process');
const { AgentBridge } = require('../src/core/agent-bridge');

const senderPath = path.join(__dirname, '..', 'native', 'build', process.arch, 'blobfish-agent-event-sender');
if (process.platform === 'darwin' && !fs.existsSync(senderPath)) {
  execFileSync(process.execPath, [path.join(__dirname, '..', 'scripts', 'build-agent-sender.js'), process.arch]);
}

function runSender(socketPath, input) {
  return new Promise((resolve, reject) => {
    const child = spawn(senderPath, ['--provider', 'codex'], {
      env: {
        HOME: os.homedir(),
        PATH: '/usr/bin:/bin',
        BLOBFISH_SOCKET: socketPath,
      },
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    child.stdin.end(JSON.stringify(input));
    child.on('error', reject);
    child.on('exit', (code) => code === 0 ? resolve() : reject(new Error(`sender exited ${code}`)));
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
    await runSender(socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: 'session-hook',
      turn_id: 'turn-hook',
      prompt: '整理发布说明',
      transcript_path: '/private/transcript.jsonl',
    });
    await runSender(socketPath, {
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
