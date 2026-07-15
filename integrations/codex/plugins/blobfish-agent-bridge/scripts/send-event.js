const net = require('net');
const os = require('os');
const path = require('path');

const MAX_INPUT_BYTES = 2 * 1024 * 1024;
const providerIndex = process.argv.indexOf('--provider');
const provider = providerIndex >= 0 ? process.argv[providerIndex + 1] : 'codex';
const socketPath = process.env.BLOBFISH_SOCKET || path.join(
  os.homedir(),
  'Library',
  'Application Support',
  'BlobfishDesktopPet',
  'agent-events.sock',
);

function finish() {
  process.exitCode = 0;
}

function mapEvent(input) {
  const eventName = input.hook_event_name;
  if (eventName === 'UserPromptSubmit') return 'started';
  if (eventName === 'PermissionRequest') return 'needs_input';
  if (eventName === 'PostToolUse' || eventName === 'PostToolUseFailure') return 'running';
  if (eventName === 'StopFailure') return 'failed';
  if (eventName === 'Stop') return 'ended';
  return null;
}

function send(input) {
  const event = mapEvent(input);
  const sessionId = typeof input.session_id === 'string' ? input.session_id : null;
  if (!event || !sessionId || !['codex', 'claude-code'].includes(provider)) return finish();

  const payload = {
    version: 1,
    provider,
    event,
    sessionId,
    timestamp: Date.now(),
  };
  if (typeof input.turn_id === 'string') payload.turnId = input.turn_id;

  const socket = net.createConnection(socketPath);
  const timeout = setTimeout(() => socket.destroy(), 300);
  socket.on('connect', () => socket.end(`${JSON.stringify(payload)}\n`));
  socket.on('error', () => {});
  socket.on('close', () => {
    clearTimeout(timeout);
    finish();
  });
}

let inputText = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  inputText += chunk;
  if (Buffer.byteLength(inputText) > MAX_INPUT_BYTES) {
    inputText = '';
    process.stdin.destroy();
    finish();
  }
});
process.stdin.on('end', () => {
  if (!inputText) return finish();
  try {
    send(JSON.parse(inputText));
  } catch {
    finish();
  }
});
