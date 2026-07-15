# macOS system integrations

## Lock and wake

The Electron main process listens to macOS lock, unlock, suspend and resume
events. Movement pauses while the session is unavailable. On return, the
language engine selects a normal unlock line; a separate rare line becomes
eligible after two hours away. Quiet hours still suppress non-urgent wake
chatter.

## Battery

Battery state is read once per minute with `/usr/bin/pmset -g batt` through
`execFile` (no shell). Alerts occur at 20%, 10%, 5%, 3% and 2%, once per
discharge cycle. If polling jumps directly from above 3% to 2%, only the 2%
message is emitted. Connecting AC power resets the cycle.

Urgent battery alerts may interrupt lower-priority speech and are allowed
during quiet hours. Battery output is parsed locally and is not logged during
normal operation.

## Calendar

Calendar support is disabled by default. Enabling it in Settings runs the
bundled EventKit helper and lets macOS present its normal calendar permission
dialog. The app does not read Calendar database files and does not bypass a
denied or restricted authorization state.

The helper returns only events in the next 24 hours. All-day events are ignored
for start reminders. Upcoming and starting notifications are deduplicated, and
a busy-day line becomes eligible at five timed events. Event titles are shown
only when the separate “允许显示日历标题” setting is enabled. All processing
stays on the Mac.

Build the helper for the current CPU with:

```bash
npm run build:native
```

Use `npm run build:native -- x64` for the Intel helper. The build embeds the
calendar usage description, uses a project-local module cache and applies an
ad-hoc development signature. Distribution signing is handled in the packaging
stage.
