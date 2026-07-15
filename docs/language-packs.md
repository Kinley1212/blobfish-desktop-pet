# Language packs

The built-in pack is `src/packs/languages/blobfish-zh-TW`.

```text
blobfish-zh-TW/
├── manifest.json
├── style.json
├── original/       # verbatim phrases recovered from the original app
│   ├── click.json
│   ├── idle.json
│   └── schedule.json
└── additions/      # new phrases; never replaces files under original/
    ├── agents.json
    ├── calendar.json
    ├── rare.json
    └── system.json
```

Each phrase has a stable `id`, an `event`, text and optional selection metadata:

```json
{
  "id": "agent-completed-03",
  "event": "agent.completed",
  "text": "做完一個……還有 {remaining} 個。",
  "weight": 5,
  "conditions": { "remainingMin": 1 }
}
```

The loader rejects escaping paths, malformed files, duplicate IDs, invalid events,
oversized text and unsupported values. Templates only substitute primitive values
from event metadata; they never execute code.

The phrase engine applies conditions, weighted rarity, per-line cooldowns and a
20-line recent history. The speech queue lets urgent battery, failure or approval
messages interrupt idle chatter without allowing rapid clicks to build an
unbounded backlog.

`test/language-pack-loader.test.js` deliberately contains the original 8 click,
34 idle and 4 schedule strings. Any accidental edit to those originals fails the
test instead of silently changing the character.
