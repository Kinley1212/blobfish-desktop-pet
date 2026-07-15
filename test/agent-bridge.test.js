const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { AgentBridge } = require('../src/core/agent-bridge');

function runSender(senderPath, socketPath, input) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [senderPath, '--provider', 'codex'], {
      env: { ...process.env, BLOBFISH_SOCKET: socketPath },
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

test('Codex hook sender forwards only whitelisted lifecycle metadata', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-'));
  const socketPath = path.join(directory, 'events.sock');
  const received = [];
  const bridge = new AgentBridge(socketPath, { onEvent: (event) => received.push(event) });
  try {
    await bridge.start();
    const senderPath = path.join(
      __dirname,
      '..',
      'integrations',
      'codex',
      'plugins',
      'blobfish-agent-bridge',
      'scripts',
      'send-event.js',
    );
    await runSender(senderPath, socketPath, {
      hook_event_name: 'UserPromptSubmit',
      session_id: 'session-hook',
      turn_id: 'turn-hook',
      prompt: 'this must never cross the bridge',
      transcript_path: '/private/transcript.jsonl',
    });
    await runSender(senderPath, socketPath, {
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
  } finally {
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
