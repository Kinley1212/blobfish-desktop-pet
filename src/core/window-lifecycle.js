function isLiveWindow(candidate) {
  return Boolean(
    candidate
    && typeof candidate.isDestroyed === 'function'
    && !candidate.isDestroyed(),
  );
}

function bindGracefulWindowClose(window, options = {}) {
  if (!window || typeof window.on !== 'function') {
    throw new TypeError('A window with lifecycle events is required');
  }
  if (typeof options.canCloseImmediately !== 'function') {
    throw new TypeError('A close policy is required');
  }
  if (typeof options.requestQuit !== 'function') {
    throw new TypeError('A graceful quit handler is required');
  }
  const onClosed = typeof options.onClosed === 'function' ? options.onClosed : () => {};

  window.on('close', (event) => {
    if (options.canCloseImmediately()) return;
    if (event && typeof event.preventDefault === 'function') event.preventDefault();
    options.requestQuit();
  });
  window.on('closed', onClosed);
}

module.exports = {
  bindGracefulWindowClose,
  isLiveWindow,
};
