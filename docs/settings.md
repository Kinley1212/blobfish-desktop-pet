# Settings

Open settings by right-clicking the fish, clicking the fish menu-bar item, or
pressing `Command+,` while the app is active. During development, `npm start --
--settings` opens the settings window immediately. The pet intentionally stays
out of the Dock; after quitting, launch it again from Applications or enable
launch at login.

The settings window controls:

- separate workday-morning and day-off daytime first-launch greetings, including
  enable switches and forward-only time ranges;
- workdays, lunch time, off-work time and half-hour reminders;
- quiet hours, with urgent battery and approval messages exempt;
- installed language pack, idle frequency, rare lines and event categories;
- fish size, swimming speed and whether it roams with no active tasks;
- launch at login without adding a Dock icon;
- calendar, Codex and Claude Code integrations;
- detected Codex/Claude plugin state and local one-click installation (Claude's
  first install opens a visible Terminal task and then updates Settings automatically);
- separate progress for finding the tool, installing the plugin, authorizing or
  loading its Hook, and receiving a real task event;
- an independent receive switch: pausing reception does not pretend to uninstall
  the plugin, and restoring reception does not require another installation;
- whether task and calendar titles may be included in local status messages.

The window groups these controls into four keyboard-accessible sections:
character and motion, greetings and schedule, voice, and connections and
privacy. The action bar stays visible while each section scrolls independently.
At the minimum supported window size, greeting time ranges and connection cards
stack instead of overflowing horizontally.

Settings are schema-validated before writing. The app writes an atomic JSON
file with mode `0600` under Electron's per-user application-data directory.
Unknown or malformed settings do not weaken validation: the app reports a
warning and temporarily falls back to defaults without overwriting the broken
file.

The once-per-day greeting marker is kept separately from user settings in
`startup-greeting-state.json`, also with mode `0600`. It uses the local calendar
date. A day is marked only after the selected greeting enters the speech queue,
so a greeting suppressed by quiet hours is not falsely recorded as spoken.
“Day off” means a weekday not selected in the workday control; the app does not
claim to download or infer statutory holidays.

Language packs shown in the selector are discovered from `src/packs/languages`
and fully validated before they are listed or saved.

Quitting from either fish menu first selects an additive farewell line, stops
movement, displays it for 1.9 seconds and then exits. The original click, idle
and schedule phrases remain untouched.
