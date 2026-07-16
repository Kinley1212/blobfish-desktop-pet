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

  if (health === 'active') {
    return {
      verdict: '已连接',
      verdictState: 'connected',
      summary: `连接正常 · 最近状态 ${lastEventLabel}`,
      instruction: '水滴鱼已经收到真实任务状态，现在不需要做任何操作。',
      primary: { action: 'none', label: '已连接，无需操作', disabled: true },
    };
  }

  if (health === 'awaiting-event') {
    return {
      verdict: '等待验证',
      verdictState: 'waiting',
      summary: '插件已经就绪，正在等待一条真实任务状态',
      instruction: provider === 'codex'
        ? '请新建或继续一个 Codex 任务；首次使用时在 /hooks 中允许水滴鱼。收到状态后这里会自动变成“已连接”。'
        : '请重新打开 Claude Code 会话并提交一条任务。收到状态后这里会自动变成“已连接”。',
      primary: { action: 'none', label: '等待任务状态…', disabled: true },
    };
  }

  if (health === 'test-timeout') {
    return {
      verdict: '未验证',
      verdictState: 'disconnected',
      summary: '60 秒内没有收到任务状态',
      instruction: provider === 'codex'
        ? '点击“重新验证”，然后在 Codex 任务中确认 /hooks 已允许水滴鱼并继续一次任务。'
        : '点击“重新验证”，然后重新打开 Claude Code 会话并提交一条任务。',
      primary: { action: 'verify', label: '重新验证', disabled: false },
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
    case 'legacy':
      return {
        verdict: '需要升级',
        verdictState: 'disconnected',
        summary: `检测到水滴鱼旧版插件${version}`,
        instruction: '点击下面的按钮，水滴鱼会自动升级并连接；不会删除其他插件。',
        primary: { action: 'manage', label: '升级并连接', disabled: false },
      };
    case 'connected':
      return {
        verdict: '等待验证',
        verdictState: 'waiting',
        summary: `插件已安装${version}，还没有收到真实任务状态`,
        instruction: '点击“开始验证”，然后按这里出现的提示发起一条任务。',
        primary: { action: 'verify', label: '开始验证', disabled: false },
      };
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
        summary: result.operation === 'disconnect' ? 'Terminal 正在断开连接' : 'Terminal 正在自动完成连接',
        instruction: '现在不需要操作，完成后这里会自动更新。',
        primary: { action: 'none', label: '正在处理…', disabled: true },
      };
    case 'conflict':
      return {
        verdict: '需要处理',
        verdictState: 'disconnected',
        summary: '发现无法确认来源的同名插件',
        instruction: '为了安全，水滴鱼不会自动删除它。点击下面的按钮查看插件名称和处理原因。',
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
    default:
      return {
        verdict: '状态未知',
        verdictState: 'disconnected',
        summary: '暂时无法判断连接状态',
        instruction: '点击“重新检测”，水滴鱼会再检查一次。',
        primary: { action: 'refresh', label: '重新检测', disabled: false },
      };
  }
}

if (typeof window !== 'undefined') {
  window.integrationUI = Object.freeze({ describeAgentIntegration });
}
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { describeAgentIntegration };
}
