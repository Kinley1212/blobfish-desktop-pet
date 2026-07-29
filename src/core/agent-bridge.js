const fs = require('fs');
const net = require('net');
const path = require('path');
const { validateAgentEvent } = require('./agent-event-schema');

const MAX_MESSAGE_BYTES = 16 * 1024;
const DEFAULT_CONNECTION_IDLE_TIMEOUT_MS = 5_000;

class AgentBridge {
  constructor(socketPath, options = {}) {
    this.socketPath = socketPath;
    this.onEvent = options.onEvent || (() => {});
    this.onError = options.onError || (() => {});
    this.connectionIdleTimeoutMs = Number.isFinite(options.connectionIdleTimeoutMs)
      && options.connectionIdleTimeoutMs > 0
      ? Math.floor(options.connectionIdleTimeoutMs)
      : DEFAULT_CONNECTION_IDLE_TIMEOUT_MS;
    this.server = null;
    this.connections = new Set();
  }

  start() {
    if (this.server) return Promise.resolve();
    if (Buffer.byteLength(this.socketPath) > 100) {
      return Promise.reject(new Error('Agent bridge socket path is too long for macOS'));
    }

    const directory = path.dirname(this.socketPath);
    fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
    fs.chmodSync(directory, 0o700);
    if (fs.existsSync(this.socketPath)) {
      const stat = fs.lstatSync(this.socketPath);
      if (!stat.isSocket()) return Promise.reject(new Error('Agent bridge path exists and is not a socket'));
      fs.unlinkSync(this.socketPath);
    }

    this.server = net.createServer((socket) => this.handleConnection(socket));
    this.server.maxConnections = 64;
    this.server.on('error', (error) => this.onError(error));
    return new Promise((resolve, reject) => {
      const onStartupError = (error) => {
        this.server = null;
        reject(error);
      };
      this.server.once('error', onStartupError);
      this.server.listen(this.socketPath, () => {
        this.server.removeListener('error', onStartupError);
        fs.chmodSync(this.socketPath, 0o600);
        resolve();
      });
    });
  }

  handleConnection(socket) {
    this.connections.add(socket);
    socket.setTimeout(this.connectionIdleTimeoutMs, () => socket.destroy());
    socket.on('error', () => {});
    socket.on('close', () => this.connections.delete(socket));

    let buffer = Buffer.alloc(0);
    let receivedBytes = 0;
    const processFrame = (frame) => {
      const line = frame.toString('utf8');
      if (!line.trim()) return;
      try {
        this.onEvent(validateAgentEvent(JSON.parse(line)));
      } catch (error) {
        this.onError(new Error(`Rejected local agent event: ${error.message}`));
      }
    };

    socket.on('data', (chunk) => {
      const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, 'utf8');
      receivedBytes += bytes.length;
      if (receivedBytes > MAX_MESSAGE_BYTES) {
        buffer = Buffer.alloc(0);
        socket.destroy();
        return;
      }
      buffer = Buffer.concat([buffer, bytes], buffer.length + bytes.length);
      let newlineIndex = buffer.indexOf(0x0a);
      while (newlineIndex >= 0) {
        processFrame(buffer.subarray(0, newlineIndex));
        buffer = buffer.subarray(newlineIndex + 1);
        newlineIndex = buffer.indexOf(0x0a);
      }
    });
    socket.on('end', () => {
      if (buffer.length === 0) return;
      const tail = buffer;
      buffer = Buffer.alloc(0);
      processFrame(tail);
    });
  }

  stop() {
    if (!this.server) {
      this.removeSocketFile();
      return Promise.resolve();
    }
    const server = this.server;
    this.server = null;
    return new Promise((resolve) => {
      server.close(() => {
        this.removeSocketFile();
        resolve();
      });
      for (const socket of this.connections) socket.destroy();
    });
  }

  removeSocketFile() {
    if (!fs.existsSync(this.socketPath)) return;
    const stat = fs.lstatSync(this.socketPath);
    if (stat.isSocket()) fs.unlinkSync(this.socketPath);
  }
}

module.exports = {
  AgentBridge,
  DEFAULT_CONNECTION_IDLE_TIMEOUT_MS,
  MAX_MESSAGE_BYTES,
};
