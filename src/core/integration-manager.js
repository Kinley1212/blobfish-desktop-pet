const { execFile } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PLUGIN_NAME = 'blobfish-agent-bridge';
const MARKETPLACE_NAME = 'blobfish-pet';
const PROVIDERS = Object.freeze({
  codex: Object.freeze({
    cliName: 'codex',
    resourceDirectory: 'codex',
    listPluginsArgs: ['plugin', 'list', '--json'],
    listMarketplacesArgs: ['plugin', 'marketplace', 'list', '--json'],
  }),
  claude: Object.freeze({
    cliName: 'claude',
    resourceDirectory: 'claude-code',
    listPluginsArgs: ['plugin', 'list', '--json'],
    listMarketplacesArgs: ['plugin', 'marketplace', 'list', '--json'],
  }),
});

function assertProvider(provider) {
  if (!Object.prototype.hasOwnProperty.call(PROVIDERS, provider)) {
    throw new Error('不支持的代理连接类型');
  }
  return PROVIDERS[provider];
}

function findExecutable(name, options = {}) {
  const homeDirectory = options.homeDirectory || os.homedir();
  const environment = options.environment || process.env;
  const candidates = new Set();
  for (const directory of (environment.PATH || '').split(path.delimiter).filter(Boolean)) {
    candidates.add(path.join(directory, name));
  }
  for (const directory of ['/opt/homebrew/bin', '/usr/local/bin', path.join(homeDirectory, '.local', 'bin')]) {
    candidates.add(path.join(directory, name));
  }

  const nvmRoot = path.join(homeDirectory, '.nvm', 'versions', 'node');
  try {
    for (const version of fs.readdirSync(nvmRoot)) {
      candidates.add(path.join(nvmRoot, version, 'bin', name));
    }
  } catch {}

  for (const candidate of candidates) {
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return candidate;
    } catch {}
  }
  return null;
}

function runCommand(command, args, options = {}, execFileImpl = execFile) {
  return new Promise((resolve, reject) => {
    const commandDirectory = path.dirname(command);
    const environment = {
      ...process.env,
      ...options.environment,
      PATH: `${commandDirectory}${path.delimiter}${options.environment?.PATH || process.env.PATH || ''}`,
    };
    execFileImpl(command, args, {
      timeout: 30000,
      maxBuffer: 2 * 1024 * 1024,
      encoding: 'utf8',
      env: environment,
    }, (error, stdout = '', stderr = '') => {
      if (error) {
        const detail = String(stderr || error.message).trim().slice(-600);
        reject(new Error(detail || '代理 CLI 命令执行失败'));
        return;
      }
      resolve({ stdout, stderr });
    });
  });
}

function parseJson(output, label) {
  try {
    return JSON.parse(output);
  } catch {
    throw new Error(`${label} 返回了无法识别的结果，请先更新对应 CLI`);
  }
}

function replaceDirectory(source, target) {
  if (!fs.statSync(source).isDirectory()) throw new Error('内置连接插件不完整');
  const parent = path.dirname(target);
  const temporary = `${target}.installing-${process.pid}`;
  const backup = `${target}.backup-${process.pid}`;
  fs.mkdirSync(parent, { recursive: true, mode: 0o700 });
  fs.rmSync(temporary, { recursive: true, force: true });
  fs.rmSync(backup, { recursive: true, force: true });
  fs.cpSync(source, temporary, { recursive: true, errorOnExist: true });
  let movedExisting = false;
  try {
    if (fs.existsSync(target)) {
      fs.renameSync(target, backup);
      movedExisting = true;
    }
    fs.renameSync(temporary, target);
    fs.rmSync(backup, { recursive: true, force: true });
  } catch (error) {
    fs.rmSync(temporary, { recursive: true, force: true });
    if (movedExisting && !fs.existsSync(target)) fs.renameSync(backup, target);
    throw error;
  }
}

class IntegrationManager {
  constructor(options) {
    this.resourcesRoot = options.resourcesRoot;
    this.dataRoot = options.dataRoot;
    this.homeDirectory = options.homeDirectory || os.homedir();
    this.environment = options.environment || process.env;
    this.locateCli = options.locateCli || ((name) => findExecutable(name, {
      homeDirectory: this.homeDirectory,
      environment: this.environment,
    }));
    this.run = options.run || ((command, args) => runCommand(command, args, {
      environment: this.environment,
    }));
  }

  async readPlugins(provider, cliPath) {
    const definition = assertProvider(provider);
    const { stdout } = await this.run(cliPath, definition.listPluginsArgs);
    const parsed = parseJson(stdout, definition.cliName);
    const entries = provider === 'codex' ? parsed.installed : parsed;
    if (!Array.isArray(entries)) throw new Error(`${definition.cliName} 插件列表格式无效`);
    return entries;
  }

  async inspect(provider) {
    const definition = assertProvider(provider);
    const cliPath = this.locateCli(definition.cliName);
    if (!cliPath) {
      return { provider, state: 'cli-missing', cliFound: false, installed: false, enabled: false };
    }
    try {
      const entries = await this.readPlugins(provider, cliPath);
      const plugin = entries.find((entry) => (
        entry.name === PLUGIN_NAME
        || entry.pluginId?.startsWith(`${PLUGIN_NAME}@`)
        || entry.id?.startsWith(`${PLUGIN_NAME}@`)
      ));
      if (!plugin) {
        return { provider, state: 'not-installed', cliFound: true, installed: false, enabled: false };
      }
      const enabled = plugin.enabled !== false;
      return {
        provider,
        state: enabled ? 'connected' : 'disabled',
        cliFound: true,
        installed: true,
        enabled,
        pluginId: plugin.pluginId || plugin.id,
        version: plugin.version || null,
      };
    } catch (error) {
      return {
        provider,
        state: 'error',
        cliFound: true,
        installed: false,
        enabled: false,
        error: error.message,
      };
    }
  }

  async inspectAll() {
    const [codex, claude] = await Promise.all([this.inspect('codex'), this.inspect('claude')]);
    return { codex, claude };
  }

  prepare(provider) {
    const definition = assertProvider(provider);
    const source = path.join(this.resourcesRoot, definition.resourceDirectory);
    const target = path.join(this.dataRoot, definition.resourceDirectory);
    replaceDirectory(source, target);
    const marketplacePath = provider === 'codex'
      ? path.join(target, '.agents', 'plugins', 'marketplace.json')
      : path.join(target, '.claude-plugin', 'marketplace.json');
    if (!fs.existsSync(marketplacePath)) throw new Error('内置 marketplace 清单不完整');
    return { target, marketplacePath };
  }

  async install(provider) {
    const definition = assertProvider(provider);
    const cliPath = this.locateCli(definition.cliName);
    if (!cliPath) throw new Error(`没有找到 ${definition.cliName} CLI，请先安装或更新它`);

    const existing = await this.inspect(provider);
    if (existing.state === 'connected') return { ...existing, changed: false, restartRequired: false };

    const { target } = this.prepare(provider);

    const { stdout } = await this.run(cliPath, definition.listMarketplacesArgs);
    const parsedMarketplaces = parseJson(stdout, `${definition.cliName} marketplace`);
    const marketplaces = provider === 'codex' ? parsedMarketplaces.marketplaces : parsedMarketplaces;
    if (!Array.isArray(marketplaces)) throw new Error(`${definition.cliName} marketplace 列表格式无效`);
    const marketplace = marketplaces.find((entry) => entry.name === MARKETPLACE_NAME);
    const configuredRoot = marketplace?.root || marketplace?.path || marketplace?.installLocation;
    if (marketplace && configuredRoot && path.resolve(configuredRoot) !== path.resolve(target)) {
      throw new Error(`已存在同名 ${MARKETPLACE_NAME} marketplace，请先在 ${definition.cliName} 中移除冲突项`);
    }
    if (!marketplace) {
      const addArgs = provider === 'codex'
        ? ['plugin', 'marketplace', 'add', target, '--json']
        : ['plugin', 'marketplace', 'add', target, '--scope', 'user'];
      await this.run(cliPath, addArgs);
    }

    if (provider === 'claude' && existing.state === 'disabled' && existing.pluginId) {
      await this.run(cliPath, ['plugin', 'enable', existing.pluginId]);
    } else {
      const selector = `${PLUGIN_NAME}@${MARKETPLACE_NAME}`;
      const installArgs = provider === 'codex'
        ? ['plugin', 'add', selector, '--json']
        : ['plugin', 'install', selector, '--scope', 'user'];
      await this.run(cliPath, installArgs);
    }

    const installed = await this.inspect(provider);
    if (installed.state !== 'connected') {
      throw new Error(`${definition.cliName} 插件安装后仍未启用，请在其插件设置中检查`);
    }
    return {
      ...installed,
      changed: true,
      restartRequired: true,
      trustRequired: provider === 'codex',
    };
  }
}

module.exports = {
  IntegrationManager,
  MARKETPLACE_NAME,
  PLUGIN_NAME,
  findExecutable,
  parseJson,
  replaceDirectory,
  runCommand,
};
