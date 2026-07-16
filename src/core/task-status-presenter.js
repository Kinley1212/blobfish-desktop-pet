const PROVIDER_LABELS = Object.freeze({
  codex: 'Codex 任务',
  'claude-code': 'Claude Code 任务',
});

function presentTask(task, state, activeCount, includeTaskTitles) {
  if (!task) return null;
  const title = includeTaskTitles && typeof task.title === 'string' && task.title.trim()
    ? task.title.trim()
    : PROVIDER_LABELS[task.provider] || '正在处理任务';
  return {
    taskKey: task.key,
    state,
    title,
    provider: task.provider,
    additionalCount: Math.max(0, activeCount - 1),
  };
}

function getCurrentTaskStatus(tasks, includeTaskTitles) {
  if (!Array.isArray(tasks) || tasks.length === 0) return null;
  const ordered = [...tasks].sort((left, right) => (
    (Number(right.updatedAt) || 0) - (Number(left.updatedAt) || 0)
  ));
  const items = ordered.map((task) => presentTask(
    task,
    task.state === 'waiting' ? 'waiting' : 'running',
    ordered.length,
    includeTaskTitles,
  ));
  return {
    ...items[0],
    items,
  };
}

function getTerminalTaskStatus(task, state, remainingTasks, includeTaskTitles) {
  const tasks = Array.isArray(remainingTasks) ? remainingTasks : [];
  const terminal = presentTask(task, state, tasks.length + 1, includeTaskTitles);
  if (!terminal) return getCurrentTaskStatus(tasks, includeTaskTitles);
  const next = getCurrentTaskStatus(tasks, includeTaskTitles);
  return {
    ...terminal,
    items: [terminal, ...(next?.items || [])],
    next,
  };
}

module.exports = {
  getCurrentTaskStatus,
  getTerminalTaskStatus,
  presentTask,
};
