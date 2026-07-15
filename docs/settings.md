# Settings

Open settings from the fish menu-bar item or press `Command+,` while the app
is active. During development, `npm start -- --settings` opens the settings
window immediately.

The settings window controls:

- workdays, lunch time, off-work time and half-hour reminders;
- quiet hours, with urgent battery and approval messages exempt;
- installed language pack, idle frequency, rare lines and event categories;
- swimming speed and the eventual all-tasks-complete stop behavior;
- calendar, Codex and Claude Code integrations;
- whether task and calendar titles may be included in local status messages.

Settings are schema-validated before writing. The app writes an atomic JSON
file with mode `0600` under Electron's per-user application-data directory.
Unknown or malformed settings do not weaken validation: the app reports a
warning and temporarily falls back to defaults without overwriting the broken
file.

Language packs shown in the selector are discovered from `src/packs/languages`
and fully validated before they are listed or saved.
