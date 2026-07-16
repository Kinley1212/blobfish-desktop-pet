class TaskTracker {
  constructor(onTransition = () => {}) {
    this.onTransition = onTransition;
    this.tasks = new Map();
  }

  taskKey(event) {
    return `${event.provider}:${event.sessionId}:${event.turnId || 'session'}`;
  }

  handle(event) {
    const key = this.taskKey(event);
    const existing = this.tasks.get(key);
    const now = event.timestamp || Date.now();
    let transition = null;
    let transitionTask = null;

    const updateTask = (task, state) => {
      task.state = state;
      task.updatedAt = now;
      if (event.title) task.title = event.title;
      return task;
    };

    if (event.event === 'started') {
      if (!existing) {
        const task = { ...event, key, state: 'running', startedAt: now, updatedAt: now };
        this.tasks.set(key, task);
        transitionTask = task;
        transition = 'started';
      } else {
        transitionTask = updateTask(existing, 'running');
      }
    } else if (event.event === 'running') {
      if (existing) {
        transitionTask = updateTask(existing, 'running');
      } else {
        const task = { ...event, key, state: 'running', startedAt: now, updatedAt: now };
        this.tasks.set(key, task);
        transitionTask = task;
        transition = 'started';
      }
    } else if (event.event === 'needs_input') {
      if (existing && existing.state !== 'waiting') transition = 'needsInput';
      if (!existing) transition = 'needsInput';
      const task = existing || { ...event, key, startedAt: now };
      updateTask(task, 'waiting');
      this.tasks.set(key, task);
      transitionTask = task;
    } else if (event.event === 'ended' || event.event === 'completed' || event.event === 'failed') {
      if (!existing) return this.snapshot();
      transitionTask = updateTask(existing, event.event);
      this.tasks.delete(key);
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
    if (changed) this.onTransition({ type: 'state', event: null, snapshot: this.snapshot() });
  }

  pruneStale(maxAgeMs, now = Date.now()) {
    let removed = 0;
    for (const [key, task] of this.tasks) {
      if (now - task.updatedAt > maxAgeMs) {
        this.tasks.delete(key);
        removed += 1;
      }
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

module.exports = { TaskTracker };
