(function exposeRendererRuntime(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.rendererRuntime = api;
}(typeof globalThis === 'object' ? globalThis : this, () => {
  function createChatInviteIntent(options = {}) {
    const now = options.now || (() => performance.now());
    let expiresAt = 0;

    return Object.freeze({
      activate(durationMs) {
        const duration = Number(durationMs);
        expiresAt = Number.isFinite(duration) && duration > 0 ? now() + duration : 0;
      },
      invalidate() {
        expiresAt = 0;
      },
      consume() {
        if (expiresAt === 0 || now() >= expiresAt) {
          expiresAt = 0;
          return false;
        }
        expiresAt = 0;
        return true;
      },
    });
  }

  function createAsyncGuard(options = {}) {
    const reportError = typeof options.reportError === 'function' ? options.reportError : () => {};
    const now = options.now || Date.now;
    const requestedCooldown = Number(options.noticeCooldownMs);
    const noticeCooldownMs = Number.isFinite(requestedCooldown)
      ? Math.max(0, requestedCooldown)
      : 2500;
    let lastNoticeAt = Number.NEGATIVE_INFINITY;

    return Object.freeze({
      async run(label, operation, details = {}) {
        try {
          return await operation();
        } catch (error) {
          const timestamp = now();
          const shouldNotify = timestamp - lastNoticeAt >= noticeCooldownMs;
          if (shouldNotify) lastNoticeAt = timestamp;
          reportError({
            error,
            label,
            shouldNotify,
            userMessage: details.userMessage,
          });
          return undefined;
        }
      },
    });
  }

  function bootstrapRenderer(options) {
    const {
      applyAgentState,
      applyPetConfig,
      guard,
      installCharacterPack,
      petAPI,
      renderTaskStatus,
    } = options;
    const stateReady = guard.run(
      'read agent state',
      async () => applyAgentState(await petAPI.getAgentState()),
    );
    const taskReady = guard.run(
      'read task status',
      async () => renderTaskStatus(await petAPI.getTaskStatus()),
    );
    const configReady = guard.run(
      'read pet config',
      async () => applyPetConfig(await petAPI.getPetConfig()),
      { userMessage: '形象設定沒有接上……' },
    );
    const characterReady = guard.run(
      'install character pack',
      installCharacterPack,
      { userMessage: '形象包壞掉了……' },
    );

    return Promise.all([stateReady, taskReady, configReady, characterReady]);
  }

  return Object.freeze({
    bootstrapRenderer,
    createAsyncGuard,
    createChatInviteIntent,
  });
}));
