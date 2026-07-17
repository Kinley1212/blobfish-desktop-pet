const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  comparePluginVersions,
  IntegrationManager,
  findExecutable,
  runCommand,
  shellQuote,
} = require('../src/core/integration-manager');

test('compares connector versions without treating build metadata as a newer release', () => {
  assert.ok(comparePluginVersions('0.2.0', '0.2.1') < 0);
  assert.equal(comparePluginVersions('0.2.1+codex.1', '0.2.1+codex.2'), 0);
  assert.ok(comparePluginVersions('1.0.0', '0.2.1') > 0);
  assert.equal(comparePluginVersions('unknown', '0.2.1'), null);
});

function createResources(root, providerDirectory) {
  const source = path.join(root, providerDirectory);
  const manifestDirectory = providerDirectory === 'codex'
    ? path.join(source, '.agents', 'plugins')
    : path.join(source, '.claude-plugin');
  fs.mkdirSync(manifestDirectory, { recursive: true });
  fs.writeFileSync(path.join(manifestDirectory, 'marketplace.json'), '{}');
  fs.writeFileSync(path.join(source, 'marker.txt'), providerDirectory);
}

test('findExecutable discovers CLIs installed inside an nvm Node version', () => {
  const homeDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-cli-'));
  try {
    const executable = path.join(homeDirectory, '.nvm', 'versions', 'node', 'v24.0.0', 'bin', 'claude');
    fs.mkdirSync(path.dirname(executable), { recursive: true });
    fs.writeFileSync(executable, '#!/bin/sh\n');
    fs.chmodSync(executable, 0o755);
    assert.equal(findExecutable('claude', { homeDirectory, environment: { PATH: '' } }), executable);
  } finally {
    fs.rmSync(homeDirectory, { recursive: true, force: true });
  }
});

test('runCommand ignores stdin and applies non-interactive CLI settings', async () => {
  let capturedOptions;
  const result = await runCommand('/fake/claude', ['plugin', 'list', '--json'], {
    environment: { PATH: '/usr/bin' },
    timeoutMs: 8000,
  }, (_command, _args, options, callback) => {
    capturedOptions = options;
    queueMicrotask(() => callback(null, '[]', ''));
  });

  assert.equal(result.stdout, '[]');
  assert.deepEqual(capturedOptions.stdio, ['ignore', 'pipe', 'pipe']);
  assert.equal(capturedOptions.timeout, 8000);
  assert.equal(capturedOptions.env.CI, '1');
  assert.equal(capturedOptions.env.NO_COLOR, '1');
  assert.equal(capturedOptions.env.TERM, 'dumb');
});

test('Claude status is read locally without launching its CLI from the GUI app', async () => {
  const homeDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-claude-local-'));
  const pluginId = 'blobfish-agent-bridge@blobfish-pet';
  const pluginRoot = path.join(homeDirectory, '.claude', 'plugins', 'cache', 'blobfish-pet', 'blobfish-agent-bridge', '0.2.0');
  fs.mkdirSync(path.join(pluginRoot, '.claude-plugin'), { recursive: true });
  fs.writeFileSync(path.join(homeDirectory, '.claude', 'settings.json'), JSON.stringify({ enabledPlugins: { [pluginId]: true } }));
  fs.writeFileSync(path.join(pluginRoot, '.claude-plugin', 'plugin.json'), JSON.stringify({ name: 'blobfish-agent-bridge', version: '0.2.0' }));
  const manager = new IntegrationManager({
    resourcesRoot: '/unused',
    dataRoot: '/unused',
    homeDirectory,
    locateCli: () => '/fake/claude',
    run: async () => { throw new Error('CLI must not run during local Claude inspection'); },
  });
  try {
    const result = await manager.inspect('claude');
    assert.equal(result.state, 'connected');
    assert.equal(result.pluginId, pluginId);
    assert.equal(result.version, '0.2.0');
  } finally {
    fs.rmSync(homeDirectory, { recursive: true, force: true });
  }
});

test('Claude local inspection reports a same-name plugin from another source as a conflict', async () => {
  const homeDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-claude-conflict-'));
  const pluginId = 'blobfish-agent-bridge@team-marketplace';
  const pluginRoot = path.join(homeDirectory, '.claude', 'plugins', 'cache', 'team-marketplace', 'blobfish-agent-bridge', '0.2.0');
  fs.mkdirSync(path.join(pluginRoot, '.claude-plugin'), { recursive: true });
  fs.writeFileSync(path.join(homeDirectory, '.claude', 'settings.json'), JSON.stringify({ enabledPlugins: { [pluginId]: true } }));
  fs.writeFileSync(path.join(pluginRoot, '.claude-plugin', 'plugin.json'), JSON.stringify({ name: 'blobfish-agent-bridge', version: '0.2.0' }));
  const manager = new IntegrationManager({
    resourcesRoot: '/unused',
    dataRoot: '/unused',
    homeDirectory,
    locateCli: () => '/fake/claude',
  });
  try {
    const result = await manager.inspect('claude');
    assert.equal(result.state, 'conflict');
    assert.equal(result.pluginId, pluginId);
  } finally {
    fs.rmSync(homeDirectory, { recursive: true, force: true });
  }
});

test('Claude local inspection recognizes the verified 0.1 plugin as a legacy waterdrop-fish install', async () => {
  const homeDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-claude-legacy-'));
  const pluginId = 'blobfish-agent-bridge@blobfish-local';
  const pluginRoot = path.join(homeDirectory, '.claude', 'plugins', 'cache', 'blobfish-local', 'blobfish-agent-bridge', '0.1.0');
  fs.mkdirSync(path.join(pluginRoot, '.claude-plugin'), { recursive: true });
  fs.writeFileSync(path.join(homeDirectory, '.claude', 'settings.json'), JSON.stringify({ enabledPlugins: { [pluginId]: true } }));
  fs.writeFileSync(path.join(pluginRoot, '.claude-plugin', 'plugin.json'), JSON.stringify({
    name: 'blobfish-agent-bridge',
    version: '0.1.0',
    author: { name: 'Blobfish Desktop Pet' },
  }));
  const manager = new IntegrationManager({
    resourcesRoot: '/unused',
    dataRoot: '/unused',
    homeDirectory,
    locateCli: () => '/fake/claude',
  });
  try {
    const result = await manager.inspect('claude');
    assert.equal(result.state, 'legacy');
    assert.equal(result.pluginId, pluginId);
    assert.equal(result.version, '0.1.0');
  } finally {
    fs.rmSync(homeDirectory, { recursive: true, force: true });
  }
});

test('Claude legacy selector without ownership metadata remains a conflict', async () => {
  const homeDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-claude-unverified-'));
  const pluginId = 'blobfish-agent-bridge@blobfish-local';
  const pluginRoot = path.join(homeDirectory, '.claude', 'plugins', 'cache', 'blobfish-local', 'blobfish-agent-bridge', '0.1.0');
  fs.mkdirSync(path.join(pluginRoot, '.claude-plugin'), { recursive: true });
  fs.writeFileSync(path.join(homeDirectory, '.claude', 'settings.json'), JSON.stringify({ enabledPlugins: { [pluginId]: true } }));
  fs.writeFileSync(path.join(pluginRoot, '.claude-plugin', 'plugin.json'), JSON.stringify({
    name: 'blobfish-agent-bridge',
    version: '0.1.0',
  }));
  const manager = new IntegrationManager({
    resourcesRoot: '/unused',
    dataRoot: '/unused',
    homeDirectory,
    locateCli: () => '/fake/claude',
  });
  try {
    assert.equal((await manager.inspect('claude')).state, 'conflict');
  } finally {
    fs.rmSync(homeDirectory, { recursive: true, force: true });
  }
});

test('Claude disconnect result is read without launching its CLI from the GUI app', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-claude-disconnected-'));
  const dataRoot = path.join(directory, 'data');
  const resultDirectory = path.join(dataRoot, 'claude-code');
  fs.mkdirSync(resultDirectory, { recursive: true });
  fs.writeFileSync(path.join(resultDirectory, 'install-result.json'), JSON.stringify({ state: 'disconnected' }));
  const manager = new IntegrationManager({
    resourcesRoot: '/unused',
    dataRoot,
    homeDirectory: directory,
    locateCli: () => '/fake/claude',
    run: async () => { throw new Error('CLI must not run after a Terminal disconnect'); },
  });

  try {
    const result = await manager.inspect('claude');
    assert.equal(result.state, 'not-installed');
    assert.equal(result.cliFound, true);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('Claude Terminal installer is generated with quoted fixed paths', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "blobfish-claude-terminal-"));
  const resourcesRoot = path.join(directory, 'resources');
  createResources(resourcesRoot, 'claude-code');
  fs.writeFileSync(path.join(resourcesRoot, 'claude-code', 'blobfish-terminal-installer.js'), 'module.exports = {};\n');
  const executable = path.join(directory, "Fish's App");
  fs.writeFileSync(executable, '');
  fs.chmodSync(executable, 0o755);
  try {
    const manager = new IntegrationManager({
      resourcesRoot,
      dataRoot: path.join(directory, 'data'),
      locateCli: () => '/fake/claude',
    });
    const prepared = manager.prepareClaudeTerminalInstaller(executable);
    const script = fs.readFileSync(prepared.commandPath, 'utf8');
    assert.match(script, /ELECTRON_RUN_AS_NODE=1/);
    assert.ok(script.includes(shellQuote(executable)));
    assert.ok(script.includes("'install'"));
    assert.equal(fs.statSync(prepared.commandPath).mode & 0o777, 0o700);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

for (const provider of ['codex', 'claude']) {
  test(`${provider} local marketplace installs in one operation`, async () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), `blobfish-${provider}-`));
    const resourcesRoot = path.join(directory, 'resources');
    const dataRoot = path.join(directory, 'data');
    const providerDirectory = provider === 'codex' ? 'codex' : 'claude-code';
    createResources(resourcesRoot, providerDirectory);
    let installed = false;
    let marketplaceAdded = false;
    const calls = [];
    const manager = new IntegrationManager({
      resourcesRoot,
      dataRoot,
      homeDirectory: directory,
      locateCli: () => `/fake/${provider}`,
      run: async (_command, args) => {
        calls.push(args);
        if (args.join(' ') === 'plugin list --json') {
          const entry = provider === 'codex'
            ? { pluginId: 'blobfish-agent-bridge@blobfish-pet', name: 'blobfish-agent-bridge', enabled: true, version: '0.1.0' }
            : { id: 'blobfish-agent-bridge@blobfish-pet', enabled: true, version: '0.1.0' };
          return { stdout: JSON.stringify(provider === 'codex' ? { installed: installed ? [entry] : [] } : installed ? [entry] : []) };
        }
        if (args.join(' ') === 'plugin marketplace list --json') {
          return { stdout: JSON.stringify(provider === 'codex' ? { marketplaces: [] } : []) };
        }
        if (args.includes('marketplace') && args.includes('add')) marketplaceAdded = true;
        if ((args.includes('add') && !args.includes('marketplace')) || args.includes('install')) installed = true;
        return { stdout: '{}' };
      },
    });

    try {
      const result = await manager.install(provider);
      assert.equal(result.state, 'connected');
      assert.equal(result.changed, true);
      assert.equal(result.restartRequired, true);
      assert.equal(marketplaceAdded, true);
      assert.equal(fs.readFileSync(path.join(dataRoot, providerDirectory, 'marker.txt'), 'utf8'), providerDirectory);
      assert.ok(calls.some((args) => args.includes('blobfish-agent-bridge@blobfish-pet')));
    } finally {
      fs.rmSync(directory, { recursive: true, force: true });
    }
  });
}

for (const provider of ['codex', 'claude']) {
  test(`${provider} repair refreshes its own plugin and uninstall removes only that selector`, async () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), `blobfish-manage-${provider}-`));
    const resourcesRoot = path.join(directory, 'resources');
    const dataRoot = path.join(directory, 'data');
    const providerDirectory = provider === 'codex' ? 'codex' : 'claude-code';
    const target = path.join(dataRoot, providerDirectory);
    createResources(resourcesRoot, providerDirectory);
    let installed = true;
    const calls = [];
    const manager = new IntegrationManager({
      resourcesRoot,
      dataRoot,
      homeDirectory: directory,
      locateCli: () => `/fake/${provider}`,
      run: async (_command, args) => {
        calls.push(args);
        if (args.join(' ') === 'plugin list --json') {
          const entry = provider === 'codex'
            ? { pluginId: 'blobfish-agent-bridge@blobfish-pet', name: 'blobfish-agent-bridge', enabled: true }
            : { id: 'blobfish-agent-bridge@blobfish-pet', enabled: true };
          return { stdout: JSON.stringify(provider === 'codex' ? { installed: installed ? [entry] : [] } : installed ? [entry] : []) };
        }
        if (args.join(' ') === 'plugin marketplace list --json') {
          const marketplace = { name: 'blobfish-pet', root: target };
          return { stdout: JSON.stringify(provider === 'codex' ? { marketplaces: [marketplace] } : [marketplace]) };
        }
        if (args.includes('remove') || args.includes('uninstall')) installed = false;
        if ((args.includes('add') && !args.includes('marketplace')) || args.includes('install')) installed = true;
        return { stdout: '{}' };
      },
    });

    try {
      assert.equal((await manager.repair(provider)).state, 'connected');
      const removed = await manager.uninstall(provider);
      assert.equal(removed.state, 'not-installed');
      assert.equal(removed.changed, true);
      assert.ok(calls.some((args) => provider === 'codex'
        ? args.join(' ') === 'plugin remove blobfish-agent-bridge@blobfish-pet --json'
        : args.join(' ') === 'plugin update blobfish-agent-bridge@blobfish-pet --scope user'));
      assert.ok(calls.some((args) => provider === 'codex'
        ? args.includes('add') && args.includes('blobfish-agent-bridge@blobfish-pet')
        : args.join(' ') === 'plugin uninstall blobfish-agent-bridge@blobfish-pet --scope user'));
    } finally {
      fs.rmSync(directory, { recursive: true, force: true });
    }
  });
}

test('missing CLI is reported without modifying integration files', async () => {
  const manager = new IntegrationManager({
    resourcesRoot: '/missing/resources',
    dataRoot: '/missing/data',
    homeDirectory: '/missing/home',
    locateCli: () => null,
    run: async () => { throw new Error('must not run'); },
  });
  assert.equal((await manager.inspect('codex')).state, 'cli-missing');
  await assert.rejects(() => manager.install('codex'), /没有找到 codex CLI/);
});

test('prepare returns the copied Codex marketplace path for the app install page', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-codex-page-'));
  const resourcesRoot = path.join(directory, 'resources');
  createResources(resourcesRoot, 'codex');
  try {
    const manager = new IntegrationManager({
      resourcesRoot,
      dataRoot: path.join(directory, 'data'),
      locateCli: () => null,
    });
    const prepared = manager.prepare('codex');
    assert.equal(prepared.marketplacePath, path.join(
      directory,
      'data',
      'codex',
      '.agents',
      'plugins',
      'marketplace.json',
    ));
    assert.equal(fs.existsSync(prepared.marketplacePath), true);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('prepare injects the bundled native sender into a plugin that requires it', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-native-sender-'));
  const resourcesRoot = path.join(directory, 'resources');
  const pluginRoot = path.join(resourcesRoot, 'codex', 'plugins', 'blobfish-agent-bridge');
  const sender = path.join(directory, 'blobfish-agent-event-sender');
  createResources(resourcesRoot, 'codex');
  fs.mkdirSync(path.join(pluginRoot, 'hooks'), { recursive: true });
  fs.writeFileSync(path.join(pluginRoot, 'hooks', 'hooks.json'), JSON.stringify({ command: 'blobfish-agent-event-sender' }));
  fs.writeFileSync(sender, 'native sender');
  fs.chmodSync(sender, 0o700);
  try {
    const manager = new IntegrationManager({
      resourcesRoot,
      dataRoot: path.join(directory, 'data'),
      eventSenderPath: sender,
      locateCli: () => null,
    });
    manager.prepare('codex');
    const installedSender = path.join(directory, 'data', 'codex', 'plugins', 'blobfish-agent-bridge', 'bin', 'blobfish-agent-event-sender');
    assert.equal(fs.readFileSync(installedSender, 'utf8'), 'native sender');
    assert.equal(fs.statSync(installedSender).mode & 0o777, 0o700);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('prepare refuses an incomplete package when native sender hooks are present', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-missing-sender-'));
  const resourcesRoot = path.join(directory, 'resources');
  const pluginRoot = path.join(resourcesRoot, 'codex', 'plugins', 'blobfish-agent-bridge');
  createResources(resourcesRoot, 'codex');
  fs.mkdirSync(path.join(pluginRoot, 'hooks'), { recursive: true });
  fs.writeFileSync(path.join(pluginRoot, 'hooks', 'hooks.json'), JSON.stringify({ command: 'blobfish-agent-event-sender' }));
  try {
    const manager = new IntegrationManager({ resourcesRoot, dataRoot: path.join(directory, 'data') });
    assert.throws(() => manager.prepare('codex'), /发送器路径缺失/);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('Codex migration replaces only the verified legacy selector and leaves its marketplace intact', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-codex-migrate-'));
  const resourcesRoot = path.join(directory, 'resources');
  const dataRoot = path.join(directory, 'data');
  const legacyRoot = path.join(directory, 'legacy-plugin');
  createResources(resourcesRoot, 'codex');
  fs.mkdirSync(path.join(legacyRoot, '.codex-plugin'), { recursive: true });
  fs.writeFileSync(path.join(legacyRoot, '.codex-plugin', 'plugin.json'), JSON.stringify({
    name: 'blobfish-agent-bridge',
    version: '0.1.0',
    author: { name: 'Blobfish Desktop Pet' },
  }));
  const calls = [];
  let pluginId = 'blobfish-agent-bridge@personal';
  const manager = new IntegrationManager({
    resourcesRoot,
    dataRoot,
    homeDirectory: directory,
    locateCli: () => '/fake/codex',
    run: async (_command, args) => {
      calls.push(args);
      if (args.join(' ') === 'plugin list --json') {
        const installed = pluginId ? [{
          pluginId,
          name: 'blobfish-agent-bridge',
          version: pluginId.endsWith('@personal') ? '0.1.0' : '0.2.0',
          enabled: true,
          source: pluginId.endsWith('@personal') ? { path: legacyRoot } : undefined,
        }] : [];
        return { stdout: JSON.stringify({ installed }) };
      }
      if (args.join(' ') === 'plugin marketplace list --json') {
        return { stdout: JSON.stringify({ marketplaces: [] }) };
      }
      if (args.join(' ') === 'plugin remove blobfish-agent-bridge@personal --json') pluginId = null;
      if (args.join(' ') === 'plugin add blobfish-agent-bridge@blobfish-pet --json') pluginId = 'blobfish-agent-bridge@blobfish-pet';
      return { stdout: '{}' };
    },
  });

  try {
    const result = await manager.migrateLegacy('codex');
    assert.equal(result.state, 'connected');
    assert.equal(result.migratedFrom, 'blobfish-agent-bridge@personal');
    assert.ok(calls.some((args) => args.join(' ') === 'plugin remove blobfish-agent-bridge@personal --json'));
    assert.ok(calls.some((args) => args.join(' ') === 'plugin add blobfish-agent-bridge@blobfish-pet --json'));
    assert.equal(calls.some((args) => args.includes('marketplace') && args.includes('remove')), false);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
