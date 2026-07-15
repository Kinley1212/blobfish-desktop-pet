const fs = require('fs');
const path = require('path');

const TIME_PATTERN = /^(?:[01]\d|2[0-3]):[0-5]\d$/;
const DEFAULT_CONFIG = Object.freeze({
  version: 1,
  schedule: Object.freeze({
    workdays: Object.freeze([1, 2, 3, 4, 5]),
    lunchTime: '13:00',
    offWorkTime: '19:00',
    halfHourReminders: true,
    lunchReminder: true,
    offWorkReminder: true,
  }),
  quietHours: Object.freeze({ enabled: false, start: '22:30', end: '08:30' }),
  language: Object.freeze({
    packId: 'blobfish-zh-TW',
    idleEnabled: true,
    rareEnabled: true,
    idleMinMinutes: 12,
    idleMaxMinutes: 35,
    categories: Object.freeze({ schedule: true, system: true, calendar: true, agents: true }),
  }),
  pet: Object.freeze({ speed: 1.5, scale: 1, roamWhenNoTasks: false }),
  integrations: Object.freeze({ calendar: false, codex: true, claudeCode: true }),
  privacy: Object.freeze({ includeTaskTitles: false, includeCalendarTitles: true }),
});

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function assertObject(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`${label} must be an object`);
}

function requireBoolean(value, label) {
  if (typeof value !== 'boolean') throw new Error(`${label} must be a boolean`);
  return value;
}

function requireTime(value, label) {
  if (typeof value !== 'string' || !TIME_PATTERN.test(value)) throw new Error(`${label} must use HH:MM`);
  return value;
}

function requireNumber(value, label, min, max) {
  if (!Number.isFinite(value) || value < min || value > max) {
    throw new Error(`${label} must be between ${min} and ${max}`);
  }
  return value;
}

function requirePackId(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$/.test(value)) {
    throw new Error('language.packId is invalid');
  }
  return value;
}

function validateConfig(input) {
  assertObject(input, 'config');
  assertObject(input.schedule, 'schedule');
  assertObject(input.quietHours, 'quietHours');
  assertObject(input.language, 'language');
  assertObject(input.language.categories, 'language.categories');
  assertObject(input.pet, 'pet');
  assertObject(input.integrations, 'integrations');
  assertObject(input.privacy, 'privacy');

  if (input.version !== 1) throw new Error('Unsupported config version');
  if (!Array.isArray(input.schedule.workdays) || input.schedule.workdays.length > 7) {
    throw new Error('schedule.workdays must be an array');
  }
  const workdays = [...new Set(input.schedule.workdays)];
  if (workdays.some((day) => !Number.isInteger(day) || day < 0 || day > 6)) {
    throw new Error('schedule.workdays entries must be integers from 0 to 6');
  }

  const config = {
    version: 1,
    schedule: {
      workdays: workdays.sort((a, b) => a - b),
      lunchTime: requireTime(input.schedule.lunchTime, 'schedule.lunchTime'),
      offWorkTime: requireTime(input.schedule.offWorkTime, 'schedule.offWorkTime'),
      halfHourReminders: requireBoolean(input.schedule.halfHourReminders, 'schedule.halfHourReminders'),
      lunchReminder: requireBoolean(input.schedule.lunchReminder, 'schedule.lunchReminder'),
      offWorkReminder: requireBoolean(input.schedule.offWorkReminder, 'schedule.offWorkReminder'),
    },
    quietHours: {
      enabled: requireBoolean(input.quietHours.enabled, 'quietHours.enabled'),
      start: requireTime(input.quietHours.start, 'quietHours.start'),
      end: requireTime(input.quietHours.end, 'quietHours.end'),
    },
    language: {
      packId: requirePackId(input.language.packId),
      idleEnabled: requireBoolean(input.language.idleEnabled, 'language.idleEnabled'),
      rareEnabled: requireBoolean(input.language.rareEnabled, 'language.rareEnabled'),
      idleMinMinutes: requireNumber(input.language.idleMinMinutes, 'language.idleMinMinutes', 1, 180),
      idleMaxMinutes: requireNumber(input.language.idleMaxMinutes, 'language.idleMaxMinutes', 1, 240),
      categories: {
        schedule: requireBoolean(input.language.categories.schedule, 'language.categories.schedule'),
        system: requireBoolean(input.language.categories.system, 'language.categories.system'),
        calendar: requireBoolean(input.language.categories.calendar, 'language.categories.calendar'),
        agents: requireBoolean(input.language.categories.agents, 'language.categories.agents'),
      },
    },
    pet: {
      speed: requireNumber(input.pet.speed, 'pet.speed', 0.25, 4),
      scale: input.pet.scale === undefined
        ? DEFAULT_CONFIG.pet.scale
        : requireNumber(input.pet.scale, 'pet.scale', 0.65, 1.5),
      roamWhenNoTasks: input.pet.roamWhenNoTasks === undefined
        ? !requireBoolean(input.pet.stopWhenAllTasksComplete, 'pet.stopWhenAllTasksComplete')
        : requireBoolean(input.pet.roamWhenNoTasks, 'pet.roamWhenNoTasks'),
    },
    integrations: {
      calendar: requireBoolean(input.integrations.calendar, 'integrations.calendar'),
      codex: requireBoolean(input.integrations.codex, 'integrations.codex'),
      claudeCode: requireBoolean(input.integrations.claudeCode, 'integrations.claudeCode'),
    },
    privacy: {
      includeTaskTitles: requireBoolean(input.privacy.includeTaskTitles, 'privacy.includeTaskTitles'),
      includeCalendarTitles: requireBoolean(input.privacy.includeCalendarTitles, 'privacy.includeCalendarTitles'),
    },
  };

  if (config.language.idleMinMinutes > config.language.idleMaxMinutes) {
    throw new Error('language.idleMinMinutes cannot exceed idleMaxMinutes');
  }
  return config;
}

class ConfigStore {
  constructor(directory, options = {}) {
    this.directory = directory;
    this.filePath = path.join(directory, options.filename || 'settings.json');
    this.config = clone(DEFAULT_CONFIG);
    this.loadWarning = null;
  }

  load() {
    this.loadWarning = null;
    if (!fs.existsSync(this.filePath)) return this.get();
    try {
      this.config = validateConfig(JSON.parse(fs.readFileSync(this.filePath, 'utf8')));
    } catch (error) {
      this.loadWarning = `设置文件无效，已临时使用默认值：${error.message}`;
      console.error(this.loadWarning);
      this.config = clone(DEFAULT_CONFIG);
    }
    return this.get();
  }

  get() {
    return clone(this.config);
  }

  save(nextConfig) {
    const validated = validateConfig(nextConfig);
    fs.mkdirSync(this.directory, { recursive: true, mode: 0o700 });
    const tempPath = `${this.filePath}.${process.pid}.tmp`;
    try {
      fs.writeFileSync(tempPath, `${JSON.stringify(validated, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 });
      fs.renameSync(tempPath, this.filePath);
    } finally {
      if (fs.existsSync(tempPath)) fs.unlinkSync(tempPath);
    }
    this.config = validated;
    this.loadWarning = null;
    return this.get();
  }

  reset() {
    return this.save(clone(DEFAULT_CONFIG));
  }
}

module.exports = {
  ConfigStore,
  DEFAULT_CONFIG,
  TIME_PATTERN,
  validateConfig,
};
