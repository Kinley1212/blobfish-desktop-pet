const fs = require('fs');
const net = require('net');
const path = require('path');
const { validateAgentEvent } = require('./agent-event-schema');

const MAX_MESSAGE_BYTES = 16 * 1024;

class AgentBridge {
  constructor(socketPath, options = {}) {
    this.socketPath = socketPath;
    this.onEvent = options.onEvent || (() => {});
    this.onError = options.onError || (() => {});
    this.server = null;
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
    socket.setEncoding('utf8');
    let buffer = '';
    socket.on('data', (chunk) => {
      buffer += chunk;
      if (Buffer.byteLength(buffer) > MAX_MESSAGE_BYTES) {
        socket.destroy();
        return;
      }
      let newlineIndex = buffer.indexOf('\n');
      while (newlineIndex >= 0) {
        const line = buffer.slice(0, newlineIndex);
        buffer = buffer.slice(newlineIndex + 1);
        if (line.trim()) {
          try {
            this.onEvent(validateAgentEvent(JSON.parse(line)));
          } catch (error) {
            this.onError(new Error(`Rejected local agent event: ${error.message}`));
          }
        }
        newlineIndex = buffer.indexOf('\n');
      }
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
  MAX_MESSAGE_BYTES,
};
