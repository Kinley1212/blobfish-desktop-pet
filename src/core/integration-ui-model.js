const PROVIDER_NAMES = Object.freeze({
  codex: 'Codex',
  claude: 'Claude Code',
});

function describeAgentIntegration(provider, result = {}, options = {}) {
  const name = PROVIDER_NAMES[provider];
  if (!name) throw new Error('不支持的连接类型');
  const health = result.health || 'unavailable';
  const version = result.version ? ` v${result.version}` : '';
  const lastEventLabel = options.lastEventLabel || '刚刚';

  if (result.operationBusy) {
    return {
      verdict: result.operation === 'disconnect' ? '正在断开' : '连接中',
      verdictState: 'waiting',
      summary: provider === 'claude'
        ? '正在通过 Terminal 完成操作'
        : `正在处理 ${name} 连接`,
      instruction: '操作完成前不需要重复点击，这里会自动更新结果。',
      primary: { action: 'none', label: '正在处理…', disabled: true },
    };
  }

  switch (result.state) {
    case 'checking':
      return {
        verdict: '检测中',
        verdictState: 'checking',
        summary: `正在自动检测 ${name}…`,
        instruction: '现在不需要操作，检测完成后这里会告诉你下一步。',
        primary: { action: 'none', label: '正在检测…', disabled: true },
      };
    case 'conflict':
      return {
        verdict: '需要处理',
        verdictState: 'disconnected',
        summary: '发现无法确认来源的同名插件',
        instruction: '为了安全，水滴鱼不会自动删除它。点击下面的按钮查看准确的处理步骤。',
        primary: { action: 'details', label: '查看处理方法', disabled: false },
      };
    case 'error':
      return {
        verdict: '检测失败',
        verdictState: 'disconnected',
        summary: '连接状态检测失败',
        instruction: '点击“重新检测”；如果仍然失败，可在“连接详情”里查看具体原因。',
        primary: { action: 'refresh', label: '重新检测', disabled: false },
      };
    case 'legacy':
      return {
        verdict: '需要升级',
        verdictState: 'disconnected',
        summary: `检测到水滴鱼旧版插件${version}`,
        instruction: '点击下面的按钮，水滴鱼会自动升级并连接；不会删除其他插件。',
        primary: { action: 'manage', label: '升级并连接', disabled: false },
      };
    case 'connected':
      break;
    case 'disabled':
      return {
        verdict: '未连接',
        verdictState: 'disconnected',
        summary: '水滴鱼插件已安装，但当前被停用',
        instruction: '点击下面的按钮，水滴鱼会自动重新启用并连接。',
        primary: { action: 'manage', label: '重新启用并连接', disabled: false },
      };
    case 'not-installed':
      return {
        verdict: '未连接',
        verdictState: 'disconnected',
        summary: `已找到 ${name}，尚未安装水滴鱼插件`,
        instruction: '点击下面的按钮即可自动安装并连接。',
        primary: { action: 'manage', label: '自动安装并连接', disabled: false },
      };
    case 'cli-missing':
      if (health === 'active') break;
      return provider === 'codex'
        ? {
          verdict: '未连接',
          verdictState: 'disconnected',
          summary: '没有找到 Codex 命令行工具',
          instruction: '点击下面的按钮打开 Codex 插件页，并在那里确认安装。',
          primary: { action: 'manage', label: '在 Codex 中安装', disabled: false },
        }
        : {
          verdict: '未连接',
          verdictState: 'disconnected',
          summary: '没有找到 Claude Code 命令行工具',
          instruction: '请先安装 Claude Code；完成后点击“重新检测”。',
          primary: { action: 'refresh', label: '重新检测', disabled: false },
        };
    case 'opened':
      return {
        verdict: '等待安装',
        verdictState: 'waiting',
        summary: 'Codex 插件页已经打开',
        instruction: '请在 Codex 中确认安装；完成后回到这里点击“重新检测”。',
        primary: { action: 'refresh', label: '安装好了，重新检测', disabled: false },
      };
    case 'opened-disconnect':
      return {
        verdict: '正在断开',
        verdictState: 'waiting',
        summary: 'Codex 插件页已经打开',
        instruction: '请在 Codex 中移除水滴鱼插件；完成后回到这里点击“重新检测”。',
        primary: { action: 'refresh', label: '已经移除，重新检测', disabled: false },
      };
    case 'terminal-opened':
      return {
        verdict: result.operation === 'disconnect' ? '正在断开' : '连接中',
        verdictState: 'waiting',
        summary: provider === 'claude'
          ? (result.operation === 'disconnect' ? 'Terminal 正在断开连接' : 'Terminal 正在自动完成连接')
          : `正在处理 ${name} 连接`,
        instruction: '现在不需要操作，完成后这里会自动更新。',
        primary: { action: 'none', label: '正在处理…', disabled: true },
      };
    default:
      break;
  }

  if (result.updateAvailable) {
    const targetVersion = result.bundledVersion ? ` v${result.bundledVersion}` : '';
    return {
      verdict: '需要更新',
      verdictState: 'disconnected',
      summary: `连接插件${version}可更新至${targetVersion || '最新版'}`,
      instruction: '点击下面的按钮即可一键更新；开启任务标题后，新任务可以显示标题。',
      primary: { action: 'update', label: '一键更新连接', disabled: false },
    };
  }

  if (result.receiveEnabled === false) {
    return {
      verdict: '已暂停',
      verdictState: 'waiting',
      summary: '插件仍在，但水滴鱼当前不会接收任务状态',
      instruction: '点击下面的按钮恢复接收；不需要重新安装插件。',
      primary: { action: 'enable', label: '恢复接收任务状态', disabled: false },
    };
  }

  if (health === 'active') {
    return {
      verdict: '已验证',
      verdictState: 'connected',
      summary: `已收到真实任务状态 · 最近一次 ${lastEventLabel}`,
      instruction: '连接已经通过真实事件验证，现在不需要操作。',
      primary: { action: 'none', label: '已验证，无需操作', disabled: true },
    };
  }

  if (health === 'awaiting-event') {
    return {
      verdict: '等待验证',
      verdictState: 'waiting',
      summary: '正在等待一条真实任务状态',
      instruction: provider === 'codex'
        ? '回到 Codex，新建或继续一个任务；若出现 Hook 提示，请允许水滴鱼。'
        : '重新打开 Claude Code 会话并提交一条任务。',
      primary: { action: 'none', label: '等待任务状态…', disabled: true },
    };
  }

  if (health === 'test-timeout') {
    return {
      verdict: '未验证',
      verdictState: 'disconnected',
      summary: '60 秒内没有收到任务状态',
      instruction: provider === 'codex'
        ? '先在 Codex 的 /hooks 中允许水滴鱼，再点击“重新验证”并继续一次任务。'
        : '重新打开 Claude Code 会话后，点击“重新验证”并提交一条任务。',
      primary: { action: 'verify', label: '重新验证', disabled: false },
    };
  }

  if (result.state === 'connected') {
    return provider === 'codex'
      ? {
        verdict: '等待授权',
        verdictState: 'waiting',
        summary: `插件已安装${version}，还需要授权并验证 Hook`,
        instruction: '在 Codex 任务中输入 /hooks，允许水滴鱼；完成后点击下面的按钮。',
        primary: { action: 'verify', label: '我已授权，开始验证', disabled: false },
      }
      : {
        verdict: '等待验证',
        verdictState: 'waiting',
        summary: `插件已安装${version}，还没有收到真实任务状态`,
        instruction: '重新打开 Claude Code 会话，然后点击下面的按钮并提交一条任务。',
        primary: { action: 'verify', label: '开始验证', disabled: false },
      };
  }

  return {
    verdict: '状态未知',
    verdictState: 'disconnected',
    summary: '暂时无法判断连接状态',
    instruction: '点击“重新检测”，水滴鱼会再检查一次。',
    primary: { action: 'refresh', label: '重新检测', disabled: false },
  };
}

if (typeof window !== 'undefined') {
  window.integrationUI = Object.freeze({ describeAgentIntegration });
}
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { describeAgentIntegration };
}
