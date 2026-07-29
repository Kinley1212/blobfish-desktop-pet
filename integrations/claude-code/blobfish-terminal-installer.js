const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');

const PLUGIN_NAME = 'blobfish-agent-bridge';
const MARKETPLACE_NAME = 'blobfish-pet';
const PLUGIN_SELECTOR = `${PLUGIN_NAME}@${MARKETPLACE_NAME}`;
const LEGACY_PLUGIN_SELECTOR = `${PLUGIN_NAME}@blobfish-local`;
const PLUGIN_AUTHOR = 'Blobfish Desktop Pet';

function isOwnedPluginManifest(manifest) {
  return manifest?.name === PLUGIN_NAME
    && manifest?.author?.name === PLUGIN_AUTHOR
    && /^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/.test(String(manifest?.version || ''));
}

function getMarketplacePath(marketplace) {
  return marketplace?.root
    || marketplace?.path
    || marketplace?.installLocation
    || marketplace?.source?.path
    || null;
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

function getClaudePaths(options = {}) {
  const environment = options.environment || process.env;
  const configRoot = environment.CLAUDE_CONFIG_DIR
    || path.join(environment.HOME || process.env.HOME || '', '.claude');
  const pluginsRoot = environment.CLAUDE_CODE_PLUGIN_CACHE_DIR
    || path.join(configRoot, 'plugins');
  return {
    configRoot,
    pluginsRoot,
    settingsPath: path.join(configRoot, 'settings.json'),
  };
}

function readLatestCacheManifest(pluginsRoot, pluginId) {
  const marketplace = pluginId.slice(PLUGIN_NAME.length + 1);
  if (!/^[A-Za-z0-9._-]+$/.test(marketplace)) return null;
  const versionRoot = path.join(pluginsRoot, 'cache', marketplace, PLUGIN_NAME);
  let candidates;
  try {
    candidates = fs.readdirSync(versionRoot, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => {
        const directory = path.join(versionRoot, entry.name);
        return { directory, modifiedAt: fs.statSync(directory).mtimeMs };
      })
      .sort((left, right) => right.modifiedAt - left.modifiedAt);
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
  if (candidates.length === 0) return null;
  try {
    return readOptionalJson(
      path.join(candidates[0].directory, '.claude-plugin', 'plugin.json'),
      'Claude Code 插件清单',
    );
  } catch (error) {
    if (error.message === 'Claude Code 插件清单 格式无效') return null;
    throw error;
  }
}

function inspectConfiguredSelectors(target, options = {}) {
  const { pluginsRoot, settingsPath } = getClaudePaths(options);
  const settings = readOptionalJson(settingsPath, 'Claude Code 设置');
  const enabledPlugins = settings?.enabledPlugins;
  if (!enabledPlugins || typeof enabledPlugins !== 'object' || Array.isArray(enabledPlugins)) {
    return { owned: [], unowned: [], settingsPath };
  }
  const knownMarketplaces = readOptionalJson(
    path.join(pluginsRoot, 'known_marketplaces.json'),
    'Claude Code marketplace 设置',
  );
  const managedPath = getMarketplacePath(knownMarketplaces?.[MARKETPLACE_NAME]);
  const managedMarketplaceOwned = Boolean(managedPath)
    && path.resolve(managedPath) === path.resolve(target);
  const records = Object.keys(enabledPlugins)
    .filter((pluginId) => pluginId.startsWith(`${PLUGIN_NAME}@`))
    .map((pluginId) => {
      const manifest = readLatestCacheManifest(pluginsRoot, pluginId);
      const knownSelector = pluginId === PLUGIN_SELECTOR || pluginId === LEGACY_PLUGIN_SELECTOR;
      return {
        pluginId,
        owned: knownSelector && (
          isOwnedPluginManifest(manifest)
          || (pluginId === PLUGIN_SELECTOR && managedMarketplaceOwned)
        ),
      };
    });
  return {
    owned: records.filter((record) => record.owned).map((record) => record.pluginId),
    unowned: records.filter((record) => !record.owned).map((record) => record.pluginId),
    settingsPath,
  };
}

function removeConfiguredSelectors(target, selectors, options = {}) {
  if (selectors.length === 0) return;
  const inspected = inspectConfiguredSelectors(target, options);
  const unownedRequested = selectors.find((pluginId) => inspected.unowned.includes(pluginId));
  if (unownedRequested) {
    throw new Error(`无法验证 ${unownedRequested} 属于水滴鱼，未修改 Claude Code 设置`);
  }
  const ownedRequested = selectors.filter((pluginId) => inspected.owned.includes(pluginId));
  if (ownedRequested.length === 0) return;
  let descriptor;
  let temporary = null;
  try {
    const before = fs.lstatSync(inspected.settingsPath);
    if (!before.isFile() || before.isSymbolicLink()) {
      throw new Error('Claude Code 设置文件类型不安全，未作修改');
    }
    descriptor = fs.openSync(
      inspected.settingsPath,
      fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0),
    );
    const settings = JSON.parse(fs.readFileSync(descriptor, 'utf8'));
    const enabledPlugins = settings?.enabledPlugins;
    if (!enabledPlugins || typeof enabledPlugins !== 'object' || Array.isArray(enabledPlugins)) return;
    for (const pluginId of ownedRequested) delete enabledPlugins[pluginId];
    const after = fs.fstatSync(descriptor);
    const current = fs.lstatSync(inspected.settingsPath);
    if (before.dev !== after.dev || before.ino !== after.ino
      || before.dev !== current.dev || before.ino !== current.ino
      || before.size !== current.size || before.mtimeMs !== current.mtimeMs) {
      throw new Error('Claude Code 设置在修复期间发生变化，请重试');
    }
    temporary = `${inspected.settingsPath}.blobfish-${process.pid}`;
    fs.writeFileSync(temporary, `${JSON.stringify(settings, null, 2)}\n`, {
      encoding: 'utf8',
      mode: before.mode & 0o777,
      flag: 'wx',
    });
    const latest = fs.lstatSync(inspected.settingsPath);
    if (before.dev !== latest.dev || before.ino !== latest.ino
      || before.size !== latest.size || before.mtimeMs !== latest.mtimeMs) {
      throw new Error('Claude Code 设置在修复期间发生变化，请重试');
    }
    fs.renameSync(temporary, inspected.settingsPath);
    temporary = null;
  } catch (error) {
    if (error instanceof SyntaxError) throw new Error('Claude Code 设置格式无效');
    throw error;
  } finally {
    if (descriptor !== undefined) fs.closeSync(descriptor);
    if (temporary) {
      try { fs.unlinkSync(temporary); } catch {}
    }
  }
}

function run(command, args, execFileImpl = execFile) {
  return new Promise((resolve, reject) => {
    execFileImpl(command, args, {
      timeout: 30000,
      maxBuffer: 2 * 1024 * 1024,
      encoding: 'utf8',
      env: {
        ...process.env,
        CI: '1',
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: '1',
        DISABLE_AUTOUPDATER: '1',
        NO_COLOR: '1',
        TERM: 'dumb',
      },
      stdio: ['inherit', 'pipe', 'pipe'],
    }, (error, stdout = '', stderr = '') => {
      if (error) {
        const detail = String(stderr || error.message).trim().slice(-800);
        reject(new Error(detail || 'Claude Code 命令执行失败'));
        return;
      }
      resolve(stdout);
    });
  });
}

function parseJson(output, label) {
  try {
    return JSON.parse(output);
  } catch {
    throw new Error(`${label} 返回了无法识别的结果`);
  }
}

function writeResult(resultPath, value) {
  const temporary = `${resultPath}.tmp-${process.pid}`;
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2), { encoding: 'utf8', mode: 0o600 });
  fs.renameSync(temporary, resultPath);
}

function findPlugin(plugins) {
  if (!Array.isArray(plugins)) throw new Error('Claude Code 插件列表格式无效');
  return plugins.find((entry) => (entry.id || entry.pluginId) === PLUGIN_SELECTOR)
    || plugins.find((entry) => (
      entry.id?.startsWith(`${PLUGIN_NAME}@`) || entry.pluginId?.startsWith(`${PLUGIN_NAME}@`)
    ));
}

function findPluginById(plugins, pluginId) {
  if (!Array.isArray(plugins)) throw new Error('Claude Code 插件列表格式无效');
  return plugins.find((entry) => (entry.id || entry.pluginId) === pluginId);
}

function isOwnedLegacyPlugin(plugin) {
  if ((plugin?.id || plugin?.pluginId) !== LEGACY_PLUGIN_SELECTOR) return false;
  if (!plugin.installPath || !path.isAbsolute(plugin.installPath)) return false;
  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(path.join(plugin.installPath, '.claude-plugin', 'plugin.json'), 'utf8'));
  } catch {
    return false;
  }
  return isOwnedPluginManifest(manifest)
    && /^0\.1(?:\.|$)/.test(String(manifest.version || ''));
}

function isOwnedPluginEntry(plugin) {
  const pluginId = plugin?.id || plugin?.pluginId;
  if (pluginId !== PLUGIN_SELECTOR && pluginId !== LEGACY_PLUGIN_SELECTOR) return false;
  if (!plugin?.installPath || !path.isAbsolute(plugin.installPath)) return false;
  try {
    const manifest = JSON.parse(fs.readFileSync(path.join(plugin.installPath, '.claude-plugin', 'plugin.json'), 'utf8'));
    return isOwnedPluginManifest(manifest);
  } catch {
    return false;
  }
}

async function inspectMarketplace(cliPath, target, runCommand) {
  const marketplaceOutput = await runCommand(cliPath, ['plugin', 'marketplace', 'list', '--json']);
  const marketplaces = parseJson(marketplaceOutput, 'Claude Code marketplace');
  if (!Array.isArray(marketplaces)) throw new Error('Claude Code marketplace 列表格式无效');
  const marketplace = marketplaces.find((entry) => entry.name === MARKETPLACE_NAME);
  const configuredRoot = getMarketplacePath(marketplace);
  if (marketplace && (!configuredRoot || path.resolve(configuredRoot) !== path.resolve(target))) {
    throw new Error(`已存在同名 ${MARKETPLACE_NAME} marketplace，请先在 Claude Code 中移除冲突项`);
  }
  return { exists: Boolean(marketplace), owned: Boolean(marketplace && configuredRoot) };
}

async function ensureMarketplace(cliPath, target, runCommand, status = null) {
  const current = status || await inspectMarketplace(cliPath, target, runCommand);
  if (!current.exists) {
    await runCommand(cliPath, ['plugin', 'marketplace', 'add', target, '--scope', 'user']);
  }
}

async function installOrRepair(action, args, options = {}) {
  const [cliPath, target, resultPath] = args;
  if (![cliPath, target, resultPath].every((value) => value && path.isAbsolute(value))) {
    throw new Error('安装助手收到的路径无效');
  }
  const runCommand = options.run || run;
  const pluginOutput = await runCommand(cliPath, ['plugin', 'list', '--json']);
  const plugins = parseJson(pluginOutput, 'Claude Code 插件列表');
  if (!Array.isArray(plugins)) throw new Error('Claude Code 插件列表格式无效');
  const configured = inspectConfiguredSelectors(target, options);
  if (configured.unowned.length > 0) {
    throw new Error(`发现同名插件 ${configured.unowned[0]}，但无法验证它属于水滴鱼`);
  }
  const marketplace = await inspectMarketplace(cliPath, target, runCommand);
  const sameNamePlugins = plugins.filter((entry) => (
    (entry.id || entry.pluginId)?.startsWith(`${PLUGIN_NAME}@`)
  ));
  const unownedPlugin = sameNamePlugins.find((entry) => {
    const pluginId = entry.id || entry.pluginId;
    if (isOwnedPluginEntry(entry)) return false;
    return pluginId !== PLUGIN_SELECTOR || !marketplace.owned;
  });
  if (unownedPlugin) {
    throw new Error(`发现同名插件 ${unownedPlugin.id || unownedPlugin.pluginId}，但它不是水滴鱼管理的来源`);
  }
  const existing = findPluginById(plugins, PLUGIN_SELECTOR);
  const ownedLegacyPlugins = sameNamePlugins.filter((entry) => (
    (entry.id || entry.pluginId) !== PLUGIN_SELECTOR && isOwnedPluginEntry(entry)
  ));

  await ensureMarketplace(cliPath, target, runCommand, marketplace);
  const selectorsRepresentedByCli = new Set(sameNamePlugins.map((entry) => entry.id || entry.pluginId));
  removeConfiguredSelectors(
    target,
    configured.owned.filter((pluginId) => !selectorsRepresentedByCli.has(pluginId)),
    options,
  );
  if (existing && existing.enabled === false) {
    await runCommand(cliPath, ['plugin', 'enable', PLUGIN_SELECTOR]);
    if (action === 'repair') {
      await runCommand(cliPath, ['plugin', 'update', PLUGIN_SELECTOR, '--scope', 'user']);
    }
  } else if (existing && action === 'repair') {
    await runCommand(cliPath, ['plugin', 'update', PLUGIN_SELECTOR, '--scope', 'user']);
  } else if (!existing) {
    await runCommand(cliPath, ['plugin', 'install', PLUGIN_SELECTOR, '--scope', 'user']);
  }

  const verifiedOutput = await runCommand(cliPath, ['plugin', 'list', '--json']);
  const verified = parseJson(verifiedOutput, 'Claude Code 插件列表');
  let connected = findPlugin(verified);
  if (!connected) throw new Error('Claude Code 插件安装后仍未启用');
  if ((connected?.id || connected?.pluginId) !== PLUGIN_SELECTOR) {
    throw new Error('Claude Code 返回了同名但来源不匹配的插件');
  }
  if (connected.enabled === false) throw new Error('Claude Code 插件安装后仍未启用');
  for (const legacy of ownedLegacyPlugins) {
    await runCommand(cliPath, ['plugin', 'uninstall', legacy.id || legacy.pluginId, '--scope', 'user']);
  }
  if (ownedLegacyPlugins.length > 0) {
    const cleanedOutput = await runCommand(cliPath, ['plugin', 'list', '--json']);
    connected = findPluginById(parseJson(cleanedOutput, 'Claude Code 插件列表'), PLUGIN_SELECTOR);
    if (!connected || connected.enabled === false) {
      throw new Error('清理旧版连接后，Claude Code 新版插件未保持启用');
    }
  }
  writeResult(resultPath, { state: 'connected', pluginId: connected.id || connected.pluginId, version: connected.version || null });
  return connected;
}

async function disconnect(args, options = {}) {
  const [cliPath, target, resultPath] = args;
  if (![cliPath, target, resultPath].every((value) => value && path.isAbsolute(value))) {
    throw new Error('断开助手收到的路径无效');
  }
  const runCommand = options.run || run;
  const pluginOutput = await runCommand(cliPath, ['plugin', 'list', '--json']);
  const plugins = parseJson(pluginOutput, 'Claude Code 插件列表');
  if (!Array.isArray(plugins)) throw new Error('Claude Code 插件列表格式无效');
  const configured = inspectConfiguredSelectors(target, options);
  if (configured.unowned.length > 0) {
    throw new Error(`发现同名插件 ${configured.unowned[0]}，但无法验证它属于水滴鱼`);
  }
  const marketplace = await inspectMarketplace(cliPath, target, runCommand);
  const ownedPlugins = plugins.filter((entry) => {
    const pluginId = entry.id || entry.pluginId;
    if (!pluginId?.startsWith(`${PLUGIN_NAME}@`)) return false;
    return isOwnedPluginEntry(entry)
      || configured.owned.includes(pluginId)
      || (pluginId === PLUGIN_SELECTOR && marketplace.owned);
  });
  const unownedPlugin = plugins.find((entry) => {
    const pluginId = entry.id || entry.pluginId;
    return pluginId?.startsWith(`${PLUGIN_NAME}@`) && !ownedPlugins.includes(entry);
  });
  if (unownedPlugin) {
    throw new Error(`发现同名插件 ${unownedPlugin.id || unownedPlugin.pluginId}，但它不是水滴鱼管理的来源`);
  }
  for (const plugin of ownedPlugins) {
    await runCommand(cliPath, ['plugin', 'uninstall', plugin.id || plugin.pluginId, '--scope', 'user']);
  }
  removeConfiguredSelectors(target, configured.owned, options);
  const verifiedOutput = await runCommand(cliPath, ['plugin', 'list', '--json']);
  const verified = parseJson(verifiedOutput, 'Claude Code 插件列表');
  if (!Array.isArray(verified)) throw new Error('Claude Code 插件列表格式无效');
  const remaining = verified.find((entry) => {
    const pluginId = entry.id || entry.pluginId;
    return pluginId === PLUGIN_SELECTOR || (
      pluginId?.startsWith(`${PLUGIN_NAME}@`) && isOwnedPluginEntry(entry)
    );
  });
  if (remaining) {
    throw new Error('Claude Code 插件卸载后仍然存在');
  }
  writeResult(resultPath, { state: 'disconnected' });
  return null;
}

async function migrate(args, options = {}) {
  const [cliPath, target, resultPath] = args;
  if (![cliPath, target, resultPath].every((value) => value && path.isAbsolute(value))) {
    throw new Error('升级助手收到的路径无效');
  }
  const runCommand = options.run || run;
  const pluginOutput = await runCommand(cliPath, ['plugin', 'list', '--json']);
  const plugins = parseJson(pluginOutput, 'Claude Code 插件列表');
  const legacy = findPluginById(plugins, LEGACY_PLUGIN_SELECTOR);
  if (!legacy || !isOwnedLegacyPlugin(legacy)) {
    throw new Error('没有找到可安全升级的水滴鱼旧版插件');
  }

  await ensureMarketplace(cliPath, target, runCommand);
  await runCommand(cliPath, ['plugin', 'uninstall', LEGACY_PLUGIN_SELECTOR, '--scope', 'user']);
  try {
    const managed = findPluginById(plugins, PLUGIN_SELECTOR);
    if (!managed) {
      await runCommand(cliPath, ['plugin', 'install', PLUGIN_SELECTOR, '--scope', 'user']);
    } else if (managed.enabled === false) {
      await runCommand(cliPath, ['plugin', 'enable', PLUGIN_SELECTOR]);
    }
    const verifiedOutput = await runCommand(cliPath, ['plugin', 'list', '--json']);
    const connected = findPluginById(parseJson(verifiedOutput, 'Claude Code 插件列表'), PLUGIN_SELECTOR);
    if (!connected || connected.enabled === false) throw new Error('Claude Code 新版插件安装后仍未启用');
    writeResult(resultPath, {
      state: 'connected',
      pluginId: connected.id || connected.pluginId,
      version: connected.version || null,
      migratedFrom: LEGACY_PLUGIN_SELECTOR,
    });
    return connected;
  } catch (error) {
    try {
      await runCommand(cliPath, ['plugin', 'install', LEGACY_PLUGIN_SELECTOR, '--scope', 'user']);
    } catch (restoreError) {
      throw new Error(`${error.message}；恢复旧版也失败：${restoreError.message}`);
    }
    throw new Error(`${error.message}；已恢复旧版连接`);
  }
}

function runAction(action, args, options = {}) {
  if (action === 'install' || action === 'repair') return installOrRepair(action, args, options);
  if (action === 'migrate') return migrate(args, options);
  if (action === 'disconnect') return disconnect(args, options);
  throw new Error('不支持的 Claude Code 连接操作');
}

function install(args, options = {}) {
  return runAction('install', args, options);
}

async function main() {
  const [action, cliPath, target, resultPath] = process.argv.slice(2, 6);
  try {
    await runAction(action, [cliPath, target, resultPath]);
  } catch (error) {
    if (resultPath && path.isAbsolute(resultPath)) {
      try { writeResult(resultPath, { state: 'error', error: error.message }); } catch {}
    }
    console.error(error.message);
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = {
  disconnect,
  findPlugin,
  findPluginById,
  install,
  installOrRepair,
  isOwnedLegacyPlugin,
  migrate,
  parseJson,
  run,
  runAction,
  writeResult,
};
