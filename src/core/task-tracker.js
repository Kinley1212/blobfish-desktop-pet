const MAX_PENDING_LIFECYCLE_EVENTS = 128;
const PENDING_LIFECYCLE_MAX_AGE_MS = 30 * 1000;

class TaskTracker {
  constructor(onTransition = () => {}, options = {}) {
    this.onTransition = onTransition;
    this.tasks = new Map();
    this.terminalEvents = new Map();
    this.pendingLifecycle = new Map();
    this.clock = typeof options.now === 'function' ? options.now : Date.now;
    this.pendingLifecycleMaxAgeMs = options.pendingLifecycleMaxAgeMs
      ?? PENDING_LIFECYCLE_MAX_AGE_MS;
    this.maxPendingLifecycleEvents = options.maxPendingLifecycleEvents
      ?? MAX_PENDING_LIFECYCLE_EVENTS;
  }

  taskKey(event) {
    return `${event.provider}:${event.sessionId}`;
  }

  pendingKey(event) {
    return JSON.stringify([event.provider, event.sessionId, event.turnId || '']);
  }

  prunePendingLifecycle(now = this.clock()) {
    for (const [key, pending] of this.pendingLifecycle) {
      if (now - pending.recordedAt > this.pendingLifecycleMaxAgeMs) {
        this.pendingLifecycle.delete(key);
      }
    }
  }

  rememberPendingLifecycle(event) {
    this.prunePendingLifecycle();
    const key = this.pendingKey(event);
    const existing = this.pendingLifecycle.get(key);
    const eventAt = Number.isFinite(event.timestamp) ? event.timestamp : this.clock();
    if (
      existing
      && (
        eventAt < existing.eventAt
        || (
          eventAt === existing.eventAt
          && existing.event.event === 'needs_input'
          && event.event !== 'needs_input'
        )
      )
    ) {
      return;
    }
    this.pendingLifecycle.delete(key);
    this.pendingLifecycle.set(key, {
      event: { ...event },
      eventAt,
      recordedAt: this.clock(),
    });
    while (this.pendingLifecycle.size > this.maxPendingLifecycleEvents) {
      this.pendingLifecycle.delete(this.pendingLifecycle.keys().next().value);
    }
  }

  takePendingLifecycle(event) {
    this.prunePendingLifecycle();
    let matching = null;
    const startedAt = Number.isFinite(event.timestamp) ? event.timestamp : this.clock();
    for (const [key, pending] of this.pendingLifecycle) {
      if (
        pending.event.provider === event.provider
        && pending.event.sessionId === event.sessionId
      ) {
        if ((pending.event.turnId || null) === (event.turnId || null)) {
          this.pendingLifecycle.delete(key);
          matching = pending.event;
        } else if (startedAt >= pending.eventAt) {
          this.pendingLifecycle.delete(key);
        }
      }
    }
    return matching;
  }

  clearPendingLifecycle(event) {
    for (const [key, pending] of this.pendingLifecycle) {
      if (
        pending.event.provider === event.provider
        && pending.event.sessionId === event.sessionId
        && (
          !event.turnId
          || (pending.event.turnId || null) === event.turnId
        )
      ) {
        this.pendingLifecycle.delete(key);
      }
    }
  }

  handle(event) {
    return this.handleWithResult(event).snapshot;
  }

  handleWithResult(event) {
    const key = this.taskKey(event);
    let existing = this.tasks.get(key);
    const now = Number.isFinite(event.timestamp) ? event.timestamp : this.clock();
    const terminalEvent = event.event === 'ended' || event.event === 'completed' || event.event === 'failed';
    const terminalRecord = this.terminalEvents.get(key);
    const ignored = () => ({ accepted: false, snapshot: this.snapshot() });
    let pendingLifecycle = null;

    this.prunePendingLifecycle();
    if (terminalEvent) this.clearPendingLifecycle(event);

    if (!terminalEvent && terminalRecord) {
      const startsDifferentExplicitTurn = event.event === 'started'
        && Boolean(event.turnId)
        && Boolean(terminalRecord.turnId)
        && event.turnId !== terminalRecord.turnId;
      if (
        event.event !== 'started'
        || now < terminalRecord.eventAt
        || (now === terminalRecord.eventAt && !startsDifferentExplicitTurn)
      ) {
        return ignored();
      }
      this.terminalEvents.delete(key);
      existing = this.tasks.get(key);
    }

    if (existing && now < existing.updatedAt) return ignored();
    if (
      existing
      && event.event !== 'started'
      && event.turnId
      && existing.turnId
      && event.turnId !== existing.turnId
    ) {
      return ignored();
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
      pendingLifecycle = this.takePendingLifecycle(event);
      if (!existing) {
        const task = { ...event, key, state: 'running', startedAt: now, updatedAt: now };
        this.tasks.set(key, task);
        transitionTask = task;
        transition = 'started';
      } else {
        const startsNewTurn = Boolean(event.turnId && event.turnId !== existing.turnId);
        transitionTask = updateTask(existing, 'running');
        if (startsNewTurn) {
          if (event.title && !isGenericTitle(event.title, event.provider)) {
            transitionTask.title = event.title;
          }
          transitionTask.startedAt = now;
          transition = 'started';
        }
      }
    } else if (event.event === 'running') {
      if (!existing) {
        this.rememberPendingLifecycle(event);
        return ignored();
      }
      transitionTask = updateTask(existing, 'running');
    } else if (event.event === 'needs_input') {
      if (!existing) {
        this.rememberPendingLifecycle(event);
        return ignored();
      }
      if (existing.state !== 'waiting') transition = 'needsInput';
      transitionTask = updateTask(existing, 'waiting');
    } else if (terminalEvent) {
      if (!existing) {
        if (!terminalRecord || now > terminalRecord.eventAt) {
          this.terminalEvents.set(key, {
            eventAt: now,
            recordedAt: this.clock(),
            provider: event.provider,
            turnId: event.turnId || null,
          });
          return { accepted: true, snapshot: this.snapshot() };
        }
        return ignored();
      }
      transitionTask = updateTask(existing, event.event);
      this.tasks.delete(key);
      this.terminalEvents.set(key, {
        eventAt: now,
        recordedAt: this.clock(),
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

    if (pendingLifecycle && transitionTask) {
      const pendingAt = Number.isFinite(pendingLifecycle.timestamp)
        ? pendingLifecycle.timestamp
        : transitionTask.updatedAt;
      transitionTask.updatedAt = Math.max(transitionTask.updatedAt, pendingAt);
      if (pendingLifecycle.turnId) transitionTask.turnId = pendingLifecycle.turnId;
      if (shouldReplaceTitle(transitionTask.title, pendingLifecycle.title, pendingLifecycle.provider)) {
        transitionTask.title = pendingLifecycle.title;
      }
      if (pendingLifecycle.event === 'needs_input') {
        transitionTask.state = 'waiting';
        const waitingSnapshot = this.snapshot();
        this.onTransition({
          type: 'needsInput',
          event: pendingLifecycle,
          task: { ...transitionTask },
          snapshot: waitingSnapshot,
        });
        return { accepted: true, snapshot: waitingSnapshot };
      }
    }
    return { accepted: Boolean(transitionTask), snapshot: this.snapshot() };
  }

  restore(events) {
    const ordered = Array.isArray(events)
      ? [...events].sort((left, right) => left.timestamp - right.timestamp)
      : [];
    for (const event of ordered) {
      if (!['started', 'running', 'needs_input'].includes(event.event)) continue;
      const key = this.taskKey(event);
      const existing = this.tasks.get(key);
      const now = Number.isFinite(event.timestamp) ? event.timestamp : Date.now();
      if (existing && now <= existing.updatedAt) continue;
      const terminalRecord = this.terminalEvents.get(key);
      const differsFromTerminalTurn = terminalRecord
        && Boolean(event.turnId)
        && Boolean(terminalRecord.turnId)
        && event.turnId !== terminalRecord.turnId;
      if (terminalRecord && now <= terminalRecord.eventAt && !differsFromTerminalTurn) continue;
      if (terminalRecord) this.terminalEvents.delete(key);
      this.tasks.set(key, {
        ...event,
        key,
        state: event.event === 'needs_input' ? 'waiting' : 'running',
        startedAt: Number.isFinite(event.startedAt) ? event.startedAt : now,
        updatedAt: now,
        recovered: true,
      });
    }
    return this.snapshot();
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
    for (const [key, pending] of this.pendingLifecycle) {
      if (pending.event.provider === provider) this.pendingLifecycle.delete(key);
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
    this.prunePendingLifecycle();
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

class ProcessedAgentEvents {
  constructor(limit = 1024) {
    this.limit = limit;
    this.events = new Map();
  }

  signature(event) {
    return JSON.stringify([
      event.provider,
      event.sessionId,
      event.turnId || '',
      event.event,
      event.timestamp,
    ]);
  }

  has(event) {
    return this.events.has(this.signature(event));
  }

  remember(event) {
    const signature = this.signature(event);
    this.events.delete(signature);
    this.events.set(signature, event.provider);
    if (this.events.size <= this.limit) return;
    this.events.delete(this.events.keys().next().value);
  }

  forgetProvider(provider) {
    for (const [signature, eventProvider] of this.events) {
      if (eventProvider === provider) this.events.delete(signature);
    }
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
    '继续处理',
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

module.exports = {
  ProcessedAgentEvents,
  TaskTracker,
  isGenericTitle,
  shouldReplaceTitle,
};
