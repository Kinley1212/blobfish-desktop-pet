class TaskTracker {
  constructor(onTransition = () => {}) {
    this.onTransition = onTransition;
    this.tasks = new Map();
    this.terminalEvents = new Map();
  }

  taskKey(event) {
    return `${event.provider}:${event.sessionId}`;
  }

  handle(event) {
    const key = this.taskKey(event);
    let existing = this.tasks.get(key);
    const now = Number.isFinite(event.timestamp) ? event.timestamp : Date.now();
    const terminalEvent = event.event === 'ended' || event.event === 'completed' || event.event === 'failed';
    const terminalRecord = this.terminalEvents.get(key);

    if (!terminalEvent && terminalRecord) {
      if (event.event !== 'started' || now <= terminalRecord.eventAt) return this.snapshot();
      this.terminalEvents.delete(key);
      existing = this.tasks.get(key);
    }

    if (existing && now < existing.updatedAt) return this.snapshot();
    if (
      existing
      && event.event !== 'started'
      && event.turnId
      && existing.turnId
      && event.turnId !== existing.turnId
    ) {
      const isKnownOlderTurn = existing.supersededTurnIds?.includes(event.turnId);
      if (!terminalEvent || isKnownOlderTurn) return this.snapshot();
    }
    let transition = null;
    let transitionTask = null;

    const updateTask = (task, state) => {
      task.state = state;
      task.updatedAt = now;
      if (event.turnId) task.turnId = event.turnId;
      if (shouldReplaceTitle(task.title, event.title, event.provider)) task.title = event.title;
      return task;
    };

    if (event.event === 'started') {
      if (!existing) {
        const task = {
          ...event,
          key,
          state: 'running',
          startedAt: now,
          updatedAt: now,
          supersededTurnIds: [],
        };
        this.tasks.set(key, task);
        transitionTask = task;
        transition = 'started';
      } else {
        const startsNewTurn = Boolean(event.turnId && event.turnId !== existing.turnId);
        if (startsNewTurn && existing.turnId) {
          existing.supersededTurnIds = [
            ...(existing.supersededTurnIds || []).filter((turnId) => turnId !== existing.turnId),
            existing.turnId,
          ].slice(-8);
        }
        transitionTask = updateTask(existing, 'running');
        if (startsNewTurn) {
          transitionTask.startedAt = now;
          transition = 'started';
        }
      }
    } else if (event.event === 'running') {
      if (!existing) return this.snapshot();
      transitionTask = updateTask(existing, 'running');
    } else if (event.event === 'needs_input') {
      if (!existing) return this.snapshot();
      if (existing.state !== 'waiting') transition = 'needsInput';
      transitionTask = updateTask(existing, 'waiting');
    } else if (terminalEvent) {
      if (!existing) {
        if (!terminalRecord || now > terminalRecord.eventAt) {
          this.terminalEvents.set(key, {
            eventAt: now,
            recordedAt: Date.now(),
            provider: event.provider,
            turnId: event.turnId || null,
          });
        }
        return this.snapshot();
      }
      transitionTask = updateTask(existing, event.event);
      this.tasks.delete(key);
      this.terminalEvents.set(key, {
        eventAt: now,
        recordedAt: Date.now(),
        provider: event.provider,
        turnId: event.turnId || existing.turnId || null,
      });
      const remaining = this.tasks.size;
      if (event.event === 'failed') transition = 'failed';
      else if (event.event === 'ended') transition = remaining === 0 ? 'allEnded' : 'ended';
      else transition = remaining === 0 ? 'allCompleted' : 'completed';
    }

    const snapshot = this.snapshot();
    const task = transitionTask ? { ...transitionTask } : null;
    if (transition) this.onTransition({ type: transition, event, task, snapshot });
    else this.onTransition({ type: 'state', event, task, snapshot });
    return snapshot;
  }

  removeProvider(provider) {
    let changed = false;
    for (const [key, task] of this.tasks) {
      if (task.provider === provider) {
        this.tasks.delete(key);
        changed = true;
      }
    }
    for (const [key, terminal] of this.terminalEvents) {
      if (terminal.provider === provider) this.terminalEvents.delete(key);
    }
    if (changed) this.onTransition({ type: 'state', event: null, snapshot: this.snapshot() });
  }

  pruneStale(maxAgeMs, now = Date.now(), waitingMaxAgeMs = maxAgeMs) {
    let removed = 0;
    for (const [key, task] of this.tasks) {
      const taskMaxAgeMs = task.state === 'waiting' ? waitingMaxAgeMs : maxAgeMs;
      if (now - task.updatedAt > taskMaxAgeMs) {
        this.tasks.delete(key);
        removed += 1;
      }
    }
    for (const [key, terminal] of this.terminalEvents) {
      if (now - terminal.recordedAt > maxAgeMs) this.terminalEvents.delete(key);
    }
    if (removed) this.onTransition({ type: 'state', event: null, snapshot: this.snapshot() });
    return removed;
  }

  getTasks() {
    return [...this.tasks.values()].map((task) => ({ ...task }));
  }

  snapshot() {
    const tasks = this.getTasks();
    return Object.freeze({
      activeCount: tasks.length,
      waitingCount: tasks.filter((task) => task.state === 'waiting').length,
      runningCount: tasks.filter((task) => task.state === 'running').length,
    });
  }
}

function isGenericTitle(title, provider) {
  if (!title) return true;
  const normalized = title.trim().toLocaleLowerCase();
  const providerName = provider === 'claude-code' ? 'claude code' : 'codex';
  return new Set([
    `${providerName} 任务`,
    `${providerName} 附件任务`,
    '继续',
    '继续吧',
    '继续执行',
    '好的',
    '好',
    '确认',
  ]).has(normalized);
}

function shouldReplaceTitle(currentTitle, incomingTitle, provider) {
  if (!incomingTitle) return false;
  if (!currentTitle) return true;
  return isGenericTitle(currentTitle, provider) && !isGenericTitle(incomingTitle, provider);
}

module.exports = { TaskTracker, isGenericTitle, shouldReplaceTitle };
