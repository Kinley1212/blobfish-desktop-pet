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

function runSender(socketPath, input, provider = 'codex') {
  return new Promise((resolve, reject) => {
    const child = spawn(senderPath, ['--provider', provider], {
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

test('native Claude hook sender keeps active background work and cleans up idle or ended sessions', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-hook-claude-'));
  const socketPath = path.join(directory, 'events.sock');
  const received = [];
  const bridge = new AgentBridge(socketPath, { onEvent: (event) => received.push(event) });
  try {
    await bridge.start();
    await runSender(socketPath, {
      hook_event_name: 'Stop',
      session_id: 'claude-background',
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
        ['claude-idle', 'ended'],
        ['claude-ended', 'ended'],
      ],
    );
  } finally {
    await bridge.stop();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
