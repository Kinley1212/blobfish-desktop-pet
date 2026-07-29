const TASK_COMPLETE_SOUND_TRANSITIONS = new Set([
  'completed',
  'allCompleted',
  'ended',
  'allEnded',
]);

function getTaskSoundCue(transitionType) {
  if (transitionType === 'needsInput') return 'needsInput';
  if (TASK_COMPLETE_SOUND_TRANSITIONS.has(transitionType)) return 'taskComplete';
  return null;
}

module.exports = {
  getTaskSoundCue,
};
