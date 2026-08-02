function hasCommonPause(state) {
  return Boolean(
    state.directlyPaused
    || state.contextMenuPaused
    || state.systemPaused
    || state.hoverPaused
  );
}

function shouldPauseMovement(state) {
  return hasCommonPause(state) || Boolean(state.agentMovementPaused);
}

function shouldPauseIdleSpeech(state) {
  return hasCommonPause(state) || Boolean(state.allTasksWaiting);
}

function shouldPauseAgentMovement(snapshot, petConfig) {
  const activeCount = Math.max(0, Number(snapshot?.activeCount) || 0);
  const waitingCount = Math.max(0, Number(snapshot?.waitingCount) || 0);
  if (activeCount > 0) {
    return waitingCount === activeCount || petConfig?.roamWhenTasks === false;
  }
  return petConfig?.roamWhenNoTasks !== true;
}

module.exports = {
  shouldPauseAgentMovement,
  shouldPauseIdleSpeech,
  shouldPauseMovement,
};
