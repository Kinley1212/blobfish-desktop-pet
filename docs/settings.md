# Settings

Open settings by right-clicking the fish, clicking the fish menu-bar item, or
pressing `Command+,` while the app is active. During development, `npm start --
--settings` opens the settings window immediately. The pet intentionally stays
out of the Dock; after quitting, launch it again from Applications or enable
launch at login.

The settings window controls:

- workdays, lunch time, off-work time and half-hour reminders;
- quiet hours, with urgent battery and approval messages exempt;
- installed language pack, idle frequency, rare lines and event categories;
- fish size, swimming speed and whether it roams with no active tasks;
- launch at login without adding a Dock icon;
- calendar, Codex and Claude Code integrations;
- detected Codex/Claude plugin state and local one-click installation (Claude's
  first install opens a visible Terminal task and then updates Settings automatically);
- whether task and calendar titles may be included in local status messages.

Settings are schema-validated before writing. The app writes an atomic JSON
file with mode `0600` under Electron's per-user application-data directory.
Unknown or malformed settings do not weaken validation: the app reports a
warning and temporarily falls back to defaults without overwriting the broken
file.

Language packs shown in the selector are discovered from `src/packs/languages`
and fully validated before they are listed or saved.

Quitting from either fish menu first selects an additive farewell line, stops
movement, displays it for 1.9 seconds and then exits. The original click, idle
and schedule phrases remain untouched.
