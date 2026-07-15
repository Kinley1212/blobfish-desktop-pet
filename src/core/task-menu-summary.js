function formatProviderTaskSummary(tasks, provider, label, enabled = true) {
  if (!enabled) return `${label}：未启用`;
  const providerTasks = tasks.filter((task) => task.provider === provider);
  const waitingCount = providerTasks.filter((task) => task.state === 'waiting').length;
  const runningCount = providerTasks.filter((task) => task.state === 'running').length;
  if (providerTasks.length === 0) return `${label}：空闲`;
  if (runningCount === 0) return `${label}：等待确认 ${waitingCount}`;
  if (waitingCount === 0) return `${label}：运行 ${runningCount}`;
  return `${label}：运行 ${runningCount} · 等待 ${waitingCount}`;
}

module.exports = { formatProviderTaskSummary };
