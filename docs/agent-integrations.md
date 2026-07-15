# Codex and Claude Code task bridge

The pet listens on a local Unix socket at:

```text
~/Library/Application Support/BlobfishDesktopPet/agent-events.sock
```

The parent directory is mode `0700` and the socket is mode `0600`. There is no
TCP listener and no network service. Each newline-delimited message is capped at
16 KiB and validated against a fixed schema:

```json
{
  "version": 1,
  "provider": "codex",
  "event": "started",
  "sessionId": "session-id",
  "turnId": "turn-id",
  "timestamp": 1784100000000
}
```

Allowed providers are `codex` and `claude-code`. Allowed events are `started`,
`running`, `needs_input`, `completed` and `failed`. Hook senders intentionally
discard `prompt`, `transcript_path`, tool input/output, model name, working
directory and code. Task titles are absent unless a future trusted sender adds
one explicitly.

## Pet behavior

| Task state | Pet behavior |
| --- | --- |
| One or more running | moves and uses the `working` action |
| Every active task waiting for approval | stops and uses `waiting` |
| One of several tasks completes | speaks once and keeps moving |
| Last task completes | uses `success`, speaks, then stops |
| Task fails | uses `failed`, speaks, and stops if nothing else remains |

Duplicate waiting events do not repeat the message. Tasks older than 12 hours
without any lifecycle update are pruned. A long-running line becomes eligible
after 20 minutes. Turning off one provider in Settings removes its live tasks.

## Codex plugin

Marketplace: `integrations/codex/.agents/plugins/marketplace.json`.
Plugin source: `integrations/codex/plugins/blobfish-agent-bridge`.

The plugin was scaffolded and validated with Codex `plugin-creator`. Its default
`hooks/hooks.json` uses the documented `UserPromptSubmit`, `PermissionRequest`,
`PostToolUse` and `Stop` events. Installed plugin hooks require review and trust
inside Codex (`/hooks`) after a new task loads them.

The packaged pet exposes **一键安装** in Settings. It copies this marketplace
to the pet's private application-data directory, runs `codex plugin marketplace
add` and `codex plugin add`, then reports the verified CLI status. This is local
only and does not need an API key. A new Codex task and one `/hooks` review are
still required by Codex's hook trust boundary.

If the Codex desktop app is present but its CLI is not discoverable, the same
button prepares the local marketplace and opens the plugin's `codex://` install
page instead. The user confirms installation in Codex, starts a new task and
reviews the hook there; no terminal command is required.

Current Codex hooks do not expose a dedicated turn-failure event. `Stop` reliably
means the turn ended, but a failed tool call is not the same thing as a failed
task, so the bridge does not mislabel `PostToolUse` failures. The local schema
already accepts an explicit `failed` event for a future documented Codex event
or App Server integration.

## Claude Code plugin

Marketplace: `integrations/claude-code/.claude-plugin/marketplace.json`
(`blobfish-pet`).
Plugin source: `integrations/claude-code/blobfish-agent-bridge`.

Claude Code adds `PostToolUseFailure` as a return-to-running signal and its
dedicated `StopFailure` event maps to task failure. Validate and install with:

```bash
claude plugin validate integrations/claude-code/blobfish-agent-bridge --strict
claude plugin marketplace add /absolute/path/to/integrations/claude-code --scope user
claude plugin install blobfish-agent-bridge@blobfish-pet --scope user
```

The same two commands are run by the Settings one-click installer. It detects
Claude installed through another marketplace and will not duplicate it. Restart
the Claude Code session after a new install.

Both hook senders exit successfully when the pet is not running, so they never
block the coding agent. Set `BLOBFISH_SOCKET` only for isolated tests.
