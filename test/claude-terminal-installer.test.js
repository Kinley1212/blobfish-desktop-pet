const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { install, runAction } = require('../integrations/claude-code/blobfish-terminal-installer');

test('Claude Terminal helper checks the marketplace before installing and verifies the result', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-claude-helper-'));
  const resultPath = path.join(directory, 'result.json');
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
    const result = await install(['/fake/claude', directory, resultPath], { run });
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
  const resultPath = path.join(directory, 'result.json');
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
    await runAction('repair', ['/fake/claude', directory, resultPath], { run });
    assert.ok(calls.some((args) => args.join(' ') === 'plugin update blobfish-agent-bridge@blobfish-pet --scope user'));
    await runAction('disconnect', ['/fake/claude', directory, resultPath], { run });
    assert.ok(calls.some((args) => args.join(' ') === 'plugin uninstall blobfish-agent-bridge@blobfish-pet --scope user'));
    assert.equal(JSON.parse(fs.readFileSync(resultPath, 'utf8')).state, 'disconnected');
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('Claude Terminal helper refuses a same-name marketplace from another path', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-claude-conflict-'));
  const run = async (_command, args) => {
    if (args.join(' ') === 'plugin list --json') return '[]';
    if (args.join(' ') === 'plugin marketplace list --json') {
      return JSON.stringify([{ name: 'blobfish-pet', root: path.join(directory, 'other') }]);
    }
    throw new Error('must not continue after a marketplace conflict');
  };
  try {
    await assert.rejects(
      () => install(['/fake/claude', directory, path.join(directory, 'result.json')], { run }),
      /已存在同名 blobfish-pet marketplace/,
    );
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
