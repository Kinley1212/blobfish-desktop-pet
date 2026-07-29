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

module.exports = {
  shouldPauseIdleSpeech,
  shouldPauseMovement,
};
