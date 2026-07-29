const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { install, runAction } = require('../integrations/claude-code/blobfish-terminal-installer');

test('Claude Terminal helper checks the marketplace before installing and verifies the result', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-claude-helper-'));
  const configRoot = path.join(directory, 'config');
  const resultPath = path.join(directory, 'result.json');
  fs.mkdirSync(path.join(configRoot, 'plugins'), { recursive: true });
  fs.writeFileSync(path.join(configRoot, 'settings.json'), JSON.stringify({ enabledPlugins: {} }));
  const calls = [];
  let installed = false;
  const run = async (_command, args) => {
    calls.push(args);
    if (args.join(' ') === 'plugin marketplace list --json') return '[]';
    if (args.join(' ') === 'plugin list --json') {
      return JSON.stringify(installed ? [{ id: 'blobfish-agent-bridge@blobfish-pet', version: '0.1.0', enabled: true }] : []);
    }
    if (args.includes('install')) installed = true;
    return '';
  };

  try {
    const result = await install(['/fake/claude', directory, resultPath], {
      run,
      environment: { CLAUDE_CONFIG_DIR: configRoot },
    });
    assert.equal(result.enabled, true);
    assert.ok(calls.some((args) => args.join(' ') === `plugin marketplace add ${directory} --scope user`));
    assert.ok(calls.some((args) => args.includes('blobfish-agent-bridge@blobfish-pet')));
    assert.equal(JSON.parse(fs.readFileSync(resultPath, 'utf8')).state, 'connected');
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('Claude Terminal helper repairs and disconnects only the managed plugin', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-claude-actions-'));
  const configRoot = path.join(directory, 'config');
  const resultPath = path.join(directory, 'result.json');
  fs.mkdirSync(path.join(configRoot, 'plugins'), { recursive: true });
  fs.writeFileSync(path.join(configRoot, 'settings.json'), JSON.stringify({ enabledPlugins: {} }));
  const calls = [];
  let installed = true;
  const run = async (_command, args) => {
    calls.push(args);
    if (args.join(' ') === 'plugin marketplace list --json') {
      return JSON.stringify([{ name: 'blobfish-pet', root: directory }]);
    }
    if (args.join(' ') === 'plugin list --json') {
      return JSON.stringify(installed ? [{ id: 'blobfish-agent-bridge@blobfish-pet', enabled: true }] : []);
    }
    if (args.includes('uninstall')) installed = false;
    return '';
  };

  try {
    const options = { run, environment: { CLAUDE_CONFIG_DIR: configRoot } };
    await runAction('repair', ['/fake/claude', directory, resultPath], options);
    assert.ok(calls.some((args) => args.join(' ') === 'plugin update blobfish-agent-bridge@blobfish-pet --scope user'));
    await runAction('disconnect', ['/fake/claude', directory, resultPath], options);
    assert.ok(calls.some((args) => args.join(' ') === 'plugin uninstall blobfish-agent-bridge@blobfish-pet --scope user'));
    assert.equal(JSON.parse(fs.readFileSync(resultPath, 'utf8')).state, 'disconnected');
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('Claude Terminal helper repairs stale owned selectors when the CLI list is empty', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-claude-stale-repair-'));
  const configRoot = path.join(directory, 'config');
  const pluginsRoot = path.join(configRoot, 'plugins');
  const target = path.join(directory, 'managed-claude');
  const resultPath = path.join(directory, 'result.json');
  const managedId = 'blobfish-agent-bridge@blobfish-pet';
  const legacyId = 'blobfish-agent-bridge@blobfish-local';
  const legacyRoot = path.join(pluginsRoot, 'cache', 'blobfish-local', 'blobfish-agent-bridge', '0.2.0');
  fs.mkdirSync(path.join(legacyRoot, '.claude-plugin'), { recursive: true });
  fs.writeFileSync(path.join(configRoot, 'settings.json'), JSON.stringify({
    theme: 'dark',
    enabledPlugins: {
      [managedId]: true,
      [legacyId]: true,
      'another-plugin@team': true,
    },
  }));
  fs.writeFileSync(path.join(pluginsRoot, 'known_marketplaces.json'), JSON.stringify({
    'blobfish-pet': { source: { source: 'directory', path: target } },
  }));
  fs.writeFileSync(path.join(legacyRoot, '.claude-plugin', 'plugin.json'), JSON.stringify({
    name: 'blobfish-agent-bridge',
    version: '0.2.0',
    author: { name: 'Blobfish Desktop Pet' },
  }));
  const calls = [];
  let installed = false;
  const run = async (_command, args) => {
    calls.push(args);
    if (args.join(' ') === 'plugin marketplace list --json') {
      return JSON.stringify([{ name: 'blobfish-pet', root: target }]);
    }
    if (args.join(' ') === 'plugin list --json') {
      return JSON.stringify(installed ? [{ id: managedId, version: '0.4.0', enabled: true }] : []);
    }
    if (args.join(' ') === `plugin install ${managedId} --scope user`) installed = true;
    return '';
  };

  try {
    const result = await runAction('repair', ['/fake/claude', target, resultPath], {
      run,
      environment: { CLAUDE_CONFIG_DIR: configRoot },
    });
    assert.equal(result.id, managedId);
    assert.ok(calls.some((args) => args.join(' ') === `plugin install ${managedId} --scope user`));
    const settings = JSON.parse(fs.readFileSync(path.join(configRoot, 'settings.json'), 'utf8'));
    assert.equal(settings.enabledPlugins[managedId], undefined);
    assert.equal(settings.enabledPlugins[legacyId], undefined);
    assert.equal(settings.enabledPlugins['another-plugin@team'], true);
    assert.equal(settings.theme, 'dark');
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('Claude Terminal helper never repairs an unverified same-name selector', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-claude-unsafe-repair-'));
  const configRoot = path.join(directory, 'config');
  const target = path.join(directory, 'managed-claude');
  fs.mkdirSync(path.join(configRoot, 'plugins'), { recursive: true });
  const settingsPath = path.join(configRoot, 'settings.json');
  const original = JSON.stringify({
    enabledPlugins: { 'blobfish-agent-bridge@team-marketplace': true },
  });
  fs.writeFileSync(settingsPath, original);
  const calls = [];
  const run = async (_command, args) => {
    calls.push(args);
    if (args.join(' ') === 'plugin list --json') return '[]';
    throw new Error('must not mutate an unverified selector');
  };

  try {
    await assert.rejects(
      () => runAction('repair', ['/fake/claude', target, path.join(directory, 'result.json')], {
        run,
        environment: { CLAUDE_CONFIG_DIR: configRoot },
      }),
      /无法验证它属于水滴鱼/,
    );
    assert.equal(calls.length, 1);
    assert.equal(fs.readFileSync(settingsPath, 'utf8'), original);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('Claude Terminal helper never modifies a team selector with a forged owned-looking manifest', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-claude-team-conflict-'));
  const configRoot = path.join(directory, 'config');
  const pluginsRoot = path.join(configRoot, 'plugins');
  const target = path.join(directory, 'managed-claude');
  const teamId = 'blobfish-agent-bridge@team-marketplace';
  const teamRoot = path.join(pluginsRoot, 'cache', 'team-marketplace', 'blobfish-agent-bridge', '9.9.9');
  fs.mkdirSync(path.join(teamRoot, '.claude-plugin'), { recursive: true });
  fs.writeFileSync(path.join(teamRoot, '.claude-plugin', 'plugin.json'), JSON.stringify({
    name: 'blobfish-agent-bridge',
    version: '9.9.9',
    author: { name: 'Blobfish Desktop Pet' },
  }));
  const settingsPath = path.join(configRoot, 'settings.json');
  const original = JSON.stringify({
    theme: 'dark',
    enabledPlugins: { [teamId]: true },
  });
  fs.writeFileSync(settingsPath, original);
  const calls = [];
  const run = async (_command, args) => {
    calls.push(args);
    if (args.join(' ') === 'plugin list --json') {
      return JSON.stringify([{ id: teamId, installPath: teamRoot, enabled: true }]);
    }
    throw new Error('must not modify a third-party selector');
  };
  const options = {
    run,
    environment: { CLAUDE_CONFIG_DIR: configRoot },
  };

  try {
    await assert.rejects(
      () => runAction('repair', ['/fake/claude', target, path.join(directory, 'repair.json')], options),
      /无法验证它属于水滴鱼/,
    );
    await assert.rejects(
      () => runAction('disconnect', ['/fake/claude', target, path.join(directory, 'disconnect.json')], options),
      /无法验证它属于水滴鱼/,
    );
    assert.deepEqual(calls, [
      ['plugin', 'list', '--json'],
      ['plugin', 'list', '--json'],
    ]);
    assert.equal(fs.readFileSync(settingsPath, 'utf8'), original);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('Claude Terminal helper rejects an owned-looking team plugin reported only by the CLI', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-claude-team-cli-'));
  const configRoot = path.join(directory, 'config');
  const target = path.join(directory, 'managed-claude');
  const teamId = 'blobfish-agent-bridge@team-marketplace';
  const teamRoot = path.join(directory, 'team-plugin');
  fs.mkdirSync(path.join(configRoot, 'plugins'), { recursive: true });
  fs.mkdirSync(path.join(teamRoot, '.claude-plugin'), { recursive: true });
  fs.writeFileSync(path.join(teamRoot, '.claude-plugin', 'plugin.json'), JSON.stringify({
    name: 'blobfish-agent-bridge',
    version: '9.9.9',
    author: { name: 'Blobfish Desktop Pet' },
  }));
  const settingsPath = path.join(configRoot, 'settings.json');
  const original = JSON.stringify({ enabledPlugins: { 'another-plugin@team': true } });
  fs.writeFileSync(settingsPath, original);
  const calls = [];
  const run = async (_command, args) => {
    calls.push(args);
    if (args.join(' ') === 'plugin list --json') {
      return JSON.stringify([{ id: teamId, installPath: teamRoot, enabled: true }]);
    }
    if (args.join(' ') === 'plugin marketplace list --json') {
      return JSON.stringify([{ name: 'blobfish-pet', root: target }]);
    }
    throw new Error('must not modify a third-party CLI plugin');
  };
  const options = {
    run,
    environment: { CLAUDE_CONFIG_DIR: configRoot },
  };

  try {
    for (const action of ['repair', 'disconnect']) {
      await assert.rejects(
        () => runAction(action, ['/fake/claude', target, path.join(directory, `${action}.json`)], options),
        /不是水滴鱼管理的来源/,
      );
    }
    assert.equal(calls.some((args) => (
      args.includes('install') || args.includes('update') || args.includes('uninstall') || args.includes('enable')
    )), false);
    assert.equal(fs.readFileSync(settingsPath, 'utf8'), original);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('Claude Terminal helper refuses a same-name marketplace from another path', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-claude-conflict-'));
  const configRoot = path.join(directory, 'config');
  fs.mkdirSync(path.join(configRoot, 'plugins'), { recursive: true });
  fs.writeFileSync(path.join(configRoot, 'settings.json'), JSON.stringify({ enabledPlugins: {} }));
  const run = async (_command, args) => {
    if (args.join(' ') === 'plugin list --json') return '[]';
    if (args.join(' ') === 'plugin marketplace list --json') {
      return JSON.stringify([{ name: 'blobfish-pet', root: path.join(directory, 'other') }]);
    }
    throw new Error('must not continue after a marketplace conflict');
  };
  try {
    await assert.rejects(
      () => install(['/fake/claude', directory, path.join(directory, 'result.json')], {
        run,
        environment: { CLAUDE_CONFIG_DIR: configRoot },
      }),
      /已存在同名 blobfish-pet marketplace/,
    );
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('Claude Terminal helper migrates only the verified 0.1 waterdrop-fish plugin', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-claude-migrate-'));
  const resultPath = path.join(directory, 'result.json');
  const legacyRoot = path.join(directory, 'legacy');
  fs.mkdirSync(path.join(legacyRoot, '.claude-plugin'), { recursive: true });
  fs.writeFileSync(path.join(legacyRoot, '.claude-plugin', 'plugin.json'), JSON.stringify({
    name: 'blobfish-agent-bridge',
    version: '0.1.0',
    author: { name: 'Blobfish Desktop Pet' },
  }));
  const calls = [];
  let pluginId = 'blobfish-agent-bridge@blobfish-local';
  const run = async (_command, args) => {
    calls.push(args);
    if (args.join(' ') === 'plugin marketplace list --json') {
      return JSON.stringify([{ name: 'blobfish-pet', root: directory }]);
    }
    if (args.join(' ') === 'plugin list --json') {
      return JSON.stringify(pluginId ? [{
        id: pluginId,
        version: pluginId.endsWith('@blobfish-local') ? '0.1.0' : '0.2.0',
        enabled: true,
        installPath: pluginId.endsWith('@blobfish-local') ? legacyRoot : undefined,
      }] : []);
    }
    if (args.join(' ') === 'plugin uninstall blobfish-agent-bridge@blobfish-local --scope user') pluginId = null;
    if (args.join(' ') === 'plugin install blobfish-agent-bridge@blobfish-pet --scope user') pluginId = 'blobfish-agent-bridge@blobfish-pet';
    return '';
  };

  try {
    await runAction('migrate', ['/fake/claude', directory, resultPath], { run });
    assert.ok(calls.some((args) => args.join(' ') === 'plugin uninstall blobfish-agent-bridge@blobfish-local --scope user'));
    assert.ok(calls.some((args) => args.join(' ') === 'plugin install blobfish-agent-bridge@blobfish-pet --scope user'));
    const result = JSON.parse(fs.readFileSync(resultPath, 'utf8'));
    assert.equal(result.state, 'connected');
    assert.equal(result.migratedFrom, 'blobfish-agent-bridge@blobfish-local');
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('Claude Terminal helper refuses an unverified legacy selector', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-claude-unverified-migrate-'));
  const legacyRoot = path.join(directory, 'legacy');
  fs.mkdirSync(path.join(legacyRoot, '.claude-plugin'), { recursive: true });
  fs.writeFileSync(path.join(legacyRoot, '.claude-plugin', 'plugin.json'), JSON.stringify({
    name: 'blobfish-agent-bridge',
    version: '0.1.0',
  }));
  const calls = [];
  const run = async (_command, args) => {
    calls.push(args);
    if (args.join(' ') === 'plugin list --json') {
      return JSON.stringify([{
        id: 'blobfish-agent-bridge@blobfish-local',
        version: '0.1.0',
        enabled: true,
        installPath: legacyRoot,
      }]);
    }
    throw new Error('must not modify an unverified plugin');
  };

  try {
    await assert.rejects(
      () => runAction('migrate', ['/fake/claude', directory, path.join(directory, 'result.json')], { run }),
      /没有找到可安全升级/,
    );
    assert.equal(calls.length, 1);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
