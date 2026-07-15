const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');

const PLUGIN_NAME = 'blobfish-agent-bridge';
const MARKETPLACE_NAME = 'blobfish-pet';

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

async function install(args, options = {}) {
  const [cliPath, target, resultPath] = args;
  if (![cliPath, target, resultPath].every((value) => value && path.isAbsolute(value))) {
    throw new Error('安装助手收到的路径无效');
  }
  const runCommand = options.run || run;
  const pluginOutput = await runCommand(cliPath, ['plugin', 'list', '--json']);
  const plugins = parseJson(pluginOutput, 'Claude Code 插件列表');
  if (!Array.isArray(plugins)) throw new Error('Claude Code 插件列表格式无效');
  const existing = plugins.find((entry) => (
    entry.id?.startsWith(`${PLUGIN_NAME}@`) || entry.pluginId?.startsWith(`${PLUGIN_NAME}@`)
  ));
  if (existing && existing.enabled === false) {
    await runCommand(cliPath, ['plugin', 'enable', existing.id || existing.pluginId]);
  } else if (!existing) {
    const marketplaceOutput = await runCommand(cliPath, ['plugin', 'marketplace', 'list', '--json']);
    const marketplaces = parseJson(marketplaceOutput, 'Claude Code marketplace');
    if (!Array.isArray(marketplaces)) throw new Error('Claude Code marketplace 列表格式无效');
    const marketplace = marketplaces.find((entry) => entry.name === MARKETPLACE_NAME);
    const configuredRoot = marketplace?.root || marketplace?.path || marketplace?.installLocation;
    if (marketplace && configuredRoot && path.resolve(configuredRoot) !== path.resolve(target)) {
      throw new Error(`已存在同名 ${MARKETPLACE_NAME} marketplace，请先在 Claude Code 中移除冲突项`);
    }
    if (!marketplace) {
      await runCommand(cliPath, ['plugin', 'marketplace', 'add', target, '--scope', 'user']);
    }
    await runCommand(cliPath, ['plugin', 'install', `${PLUGIN_NAME}@${MARKETPLACE_NAME}`, '--scope', 'user']);
  }

  const verifiedOutput = await runCommand(cliPath, ['plugin', 'list', '--json']);
  const verified = parseJson(verifiedOutput, 'Claude Code 插件列表');
  const connected = Array.isArray(verified) && verified.find((entry) => (
    (entry.id?.startsWith(`${PLUGIN_NAME}@`) || entry.pluginId?.startsWith(`${PLUGIN_NAME}@`))
      && entry.enabled !== false
  ));
  if (!connected) throw new Error('Claude Code 插件安装后仍未启用');
  writeResult(resultPath, { state: 'connected', pluginId: connected.id || connected.pluginId, version: connected.version || null });
  return connected;
}

async function main() {
  const resultPath = process.argv[4];
  try {
    await install(process.argv.slice(2, 5));
  } catch (error) {
    if (resultPath && path.isAbsolute(resultPath)) {
      try { writeResult(resultPath, { state: 'error', error: error.message }); } catch {}
    }
    console.error(error.message);
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = { install, parseJson, run, writeResult };
