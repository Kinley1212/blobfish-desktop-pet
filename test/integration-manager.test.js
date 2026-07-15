const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { IntegrationManager, findExecutable } = require('../src/core/integration-manager');

function createResources(root, providerDirectory) {
  const source = path.join(root, providerDirectory);
  fs.mkdirSync(source, { recursive: true });
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

test('missing CLI is reported without modifying integration files', async () => {
  const manager = new IntegrationManager({
    resourcesRoot: '/missing/resources',
    dataRoot: '/missing/data',
    locateCli: () => null,
    run: async () => { throw new Error('must not run'); },
  });
  assert.equal((await manager.inspect('codex')).state, 'cli-missing');
  await assert.rejects(() => manager.install('codex'), /没有找到 codex CLI/);
});
