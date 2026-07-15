const { execFile } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PLUGIN_NAME = 'blobfish-agent-bridge';
const MARKETPLACE_NAME = 'blobfish-pet';
const PLUGIN_SELECTOR = `${PLUGIN_NAME}@${MARKETPLACE_NAME}`;
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
      CI: '1',
      NO_COLOR: '1',
      TERM: 'dumb',
    };
    const child = execFileImpl(command, args, {
      timeout: options.timeoutMs || 30000,
      maxBuffer: 2 * 1024 * 1024,
      encoding: 'utf8',
      env: environment,
      stdio: ['ignore', 'pipe', 'pipe'],
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

function readOptionalJson(filePath, label) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    if (error instanceof SyntaxError) throw new Error(`${label} 格式无效`);
    throw error;
  }
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
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
    this.run = options.run || ((command, args, commandOptions = {}) => runCommand(command, args, {
      environment: this.environment,
      ...commandOptions,
    }));
  }

  async readPlugins(provider, cliPath) {
    const definition = assertProvider(provider);
    const { stdout } = await this.run(cliPath, definition.listPluginsArgs, { timeoutMs: 8000 });
    const parsed = parseJson(stdout, definition.cliName);
    const entries = provider === 'codex' ? parsed.installed : parsed;
    if (!Array.isArray(entries)) throw new Error(`${definition.cliName} 插件列表格式无效`);
    return entries;
  }

  inspectClaudeLocal(cliPath) {
    const configRoot = this.environment.CLAUDE_CONFIG_DIR || path.join(this.homeDirectory, '.claude');
    const pluginsRoot = this.environment.CLAUDE_CODE_PLUGIN_CACHE_DIR || path.join(configRoot, 'plugins');
    const settings = readOptionalJson(path.join(configRoot, 'settings.json'), 'Claude Code 设置');
    const enabledPlugins = settings?.enabledPlugins;
    if (!enabledPlugins || typeof enabledPlugins !== 'object' || Array.isArray(enabledPlugins)) return null;

    const matches = Object.entries(enabledPlugins)
      .filter(([pluginId]) => pluginId.startsWith(`${PLUGIN_NAME}@`))
      .sort((left, right) => Number(right[1] === true) - Number(left[1] === true));
    if (matches.length === 0) return null;

    const [pluginId, setting] = matches[0];
    const marketplace = pluginId.slice(PLUGIN_NAME.length + 1);
    if (!/^[A-Za-z0-9._-]+$/.test(marketplace)) throw new Error('Claude Code 插件来源名称无效');
    const versionRoot = path.join(pluginsRoot, 'cache', marketplace, PLUGIN_NAME);
    let version = null;
    let installed = false;
    try {
      const candidates = fs.readdirSync(versionRoot, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => {
          const directory = path.join(versionRoot, entry.name);
          return { directory, name: entry.name, modifiedAt: fs.statSync(directory).mtimeMs };
        })
        .sort((left, right) => right.modifiedAt - left.modifiedAt);
      if (candidates.length > 0) {
        installed = true;
        const manifest = readOptionalJson(
          path.join(candidates[0].directory, '.claude-plugin', 'plugin.json'),
          'Claude Code 插件清单',
        );
        version = manifest?.version || candidates[0].name;
      }
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }

    if (!installed) throw new Error('Claude Code 已记录这个插件，但本地插件缓存不存在');
    const enabled = setting === true;
    if (pluginId !== PLUGIN_SELECTOR) {
      return {
        provider: 'claude',
        state: 'conflict',
        cliFound: Boolean(cliPath),
        installed: true,
        enabled,
        pluginId,
        version,
        error: `发现同名插件 ${pluginId}，但它不是水滴鱼管理的来源`,
      };
    }
    return {
      provider: 'claude',
      state: enabled ? 'connected' : 'disabled',
      cliFound: Boolean(cliPath),
      installed: true,
      enabled,
      pluginId,
      version,
    };
  }

  async inspect(provider) {
    const definition = assertProvider(provider);
    const cliPath = this.locateCli(definition.cliName);
    if (provider === 'claude') {
      try {
        const localStatus = this.inspectClaudeLocal(cliPath);
        if (localStatus) return localStatus;
        const installResult = readOptionalJson(
          path.join(this.dataRoot, PROVIDERS.claude.resourceDirectory, 'install-result.json'),
          'Claude Code 安装结果',
        );
        if (installResult?.state === 'error') {
          return {
            provider,
            state: 'error',
            cliFound: Boolean(cliPath),
            installed: false,
            enabled: false,
            error: installResult.error || 'Terminal 安装没有完成',
          };
        }
        if (installResult?.state === 'disconnected') {
          return {
            provider,
            state: 'not-installed',
            cliFound: Boolean(cliPath),
            installed: false,
            enabled: false,
          };
        }
      } catch (error) {
        return {
          provider,
          state: 'error',
          cliFound: Boolean(cliPath),
          installed: false,
          enabled: false,
          error: error.message,
        };
      }
    }
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
      const pluginId = plugin.pluginId || plugin.id || null;
      if (pluginId && pluginId !== PLUGIN_SELECTOR) {
        return {
          provider,
          state: 'conflict',
          cliFound: true,
          installed: true,
          enabled,
          pluginId,
          version: plugin.version || null,
          error: `发现同名插件 ${pluginId}，但它不是水滴鱼管理的来源`,
        };
      }
      return {
        provider,
        state: enabled ? 'connected' : 'disabled',
        cliFound: true,
        installed: true,
        enabled,
        pluginId,
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

  prepareClaudeTerminalInstaller(appExecutable) {
    return this.prepareClaudeTerminalAction(appExecutable, 'install');
  }

  prepareClaudeTerminalAction(appExecutable, action) {
    if (!['install', 'repair', 'disconnect'].includes(action)) throw new Error('不支持的 Claude Code 连接操作');
    const cliPath = this.locateCli(PROVIDERS.claude.cliName);
    if (!cliPath) throw new Error('没有找到 claude CLI，请先安装或更新它');
    if (!path.isAbsolute(appExecutable)) throw new Error('水滴鱼运行程序路径无效');
    fs.accessSync(appExecutable, fs.constants.X_OK);

    const { target } = this.prepare('claude');
    const helperPath = path.join(target, 'blobfish-terminal-installer.js');
    if (!fs.existsSync(helperPath)) throw new Error('内置 Claude Code 安装助手不完整');
    const resultPath = path.join(target, 'install-result.json');
    const commandPath = path.join(target, '连接水滴鱼.command');
    fs.rmSync(resultPath, { force: true });
    const script = [
      '#!/bin/zsh',
      'set -u',
      'echo "水滴鱼正在连接 Claude Code…"',
      'export ELECTRON_RUN_AS_NODE=1',
      `${shellQuote(appExecutable)} ${shellQuote(helperPath)} ${shellQuote(action)} ${shellQuote(cliPath)} ${shellQuote(target)} ${shellQuote(resultPath)}`,
      'status=$?',
      'unset ELECTRON_RUN_AS_NODE',
      'if [[ $status -eq 0 ]]; then',
      `  echo "${action === 'disconnect' ? '已经断开水滴鱼。' : '连接操作完成。重新打开 Claude Code 会话就能生效。'}"`,
      'else',
      '  echo "连接没有完成；请保留上面的错误信息。"',
      'fi',
      'echo "现在可以关闭这个窗口。"',
      'exit $status',
      '',
    ].join('\n');
    fs.writeFileSync(commandPath, script, { encoding: 'utf8', mode: 0o700 });
    fs.chmodSync(commandPath, 0o700);
    return { commandPath, resultPath };
  }

  async ensureMarketplace(provider, cliPath, target) {
    const definition = assertProvider(provider);
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
  }

  async install(provider, options = {}) {
    const definition = assertProvider(provider);
    const cliPath = this.locateCli(definition.cliName);
    if (!cliPath) throw new Error(`没有找到 ${definition.cliName} CLI，请先安装或更新它`);

    const existing = await this.inspect(provider);
    if (existing.state === 'conflict') throw new Error(existing.error);
    if (existing.state === 'connected' && !options.force) {
      return { ...existing, changed: false, restartRequired: false };
    }

    const { target } = this.prepare(provider);
    await this.ensureMarketplace(provider, cliPath, target);

    if (options.force && existing.installed) {
      if (provider === 'codex') {
        await this.run(cliPath, ['plugin', 'remove', PLUGIN_SELECTOR, '--json']);
        await this.run(cliPath, ['plugin', 'add', PLUGIN_SELECTOR, '--json']);
      } else {
        if (existing.state === 'disabled') await this.run(cliPath, ['plugin', 'enable', PLUGIN_SELECTOR]);
        await this.run(cliPath, ['plugin', 'update', PLUGIN_SELECTOR, '--scope', 'user']);
      }
    } else if (provider === 'claude' && existing.state === 'disabled' && existing.pluginId) {
      await this.run(cliPath, ['plugin', 'enable', existing.pluginId]);
    } else {
      const installArgs = provider === 'codex'
        ? ['plugin', 'add', PLUGIN_SELECTOR, '--json']
        : ['plugin', 'install', PLUGIN_SELECTOR, '--scope', 'user'];
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

  repair(provider) {
    return this.install(provider, { force: true });
  }

  async uninstall(provider) {
    const definition = assertProvider(provider);
    const cliPath = this.locateCli(definition.cliName);
    if (!cliPath) throw new Error(`没有找到 ${definition.cliName} CLI，无法自动断开`);
    const existing = await this.inspect(provider);
    if (existing.state === 'conflict') throw new Error(existing.error);
    if (!existing.installed) {
      return { ...existing, changed: false, restartRequired: false };
    }

    const args = provider === 'codex'
      ? ['plugin', 'remove', PLUGIN_SELECTOR, '--json']
      : ['plugin', 'uninstall', PLUGIN_SELECTOR, '--scope', 'user'];
    await this.run(cliPath, args);
    const removed = await this.inspect(provider);
    if (removed.installed) throw new Error(`${definition.cliName} 插件卸载后仍然存在`);
    return { ...removed, changed: true, restartRequired: true };
  }
}

module.exports = {
  IntegrationManager,
  MARKETPLACE_NAME,
  PLUGIN_NAME,
  PLUGIN_SELECTOR,
  findExecutable,
  parseJson,
  replaceDirectory,
  runCommand,
  shellQuote,
};
