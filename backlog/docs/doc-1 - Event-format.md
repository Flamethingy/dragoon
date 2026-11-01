---
id: doc-1
title: Event format
type: specification
tags:
  - events
  - decision
project: Dragoon
created_date: '2026-11-01 11:41'
updated_date: '2026-11-01 11:41'
---

How the VTT records changes on the world timeline (concept: *Timeline and calendars*, [[Dragoon Concept]]). Result of [[TASK-2]].

**Status:** proposal by Mochi, 2026-11-01. MVP event types approved by Nico on 2026-11-01 as a starting set. They will be extended for many more scenarios later. The storage decision is still open for the group to confirm.

## The rule: event or entity?

- **Entity (markdown, written by the vault program):** what something *is* when it enters the campaign: base stat block, lore, token art, size. Includes the campaign copy made by "send into campaign".
- **Event (log, written by the VTT):** anything that *happens* during play or prep in the VTT: moving, gaining or losing things, damage, levels, time passing, notes.
- The state at a moment = campaign copy + all events up to that moment. The VTT never writes play state back into the markdown.

## Event record

One JSON object per event.

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | int | Sequence number in this campaign's log, starting at 1, never reused. |
| `type` | string | `area.verb`, e.g. `token.moved`. See the types below. |
| `entity` | string | Id of the campaign entity it is about (its path in the campaign folder without `.md`, e.g. `npc/mira`). Empty string for world-wide events such as `time.advanced`. |
| `day` | int | In-world day number on the world timeline (day 0 = first day of the calendar's `first_year`). |
| `time` | int | Minutes since in-world midnight, or `-1` if unknown. |
| `real` | string | Real-world time, ISO 8601 UTC (`2026-11-07T19:42:10Z`). |
| `session` | int | Session number; `0` = prep between sessions. |
| `by` | string | Who caused it: `dm`, a player id, or `assistant:<name>`. |
| `data` | object | Type-specific payload (below). |
| `undoes` | int | *Optional.* Id of an event this one cancels. The log is append-only, so mistakes are undone by a new event, never by editing. |

**Order on the timeline:** `(day, time, id)`. Rewinding to a moment = replaying every event at or before it (`time = -1` counts as the start of its day). Positions are grid cells on the named map.

## Examples

```json
{"id": 41, "type": "token.moved", "entity": "pc/thalia", "day": 152, "time": 870, "real": "2026-11-07T19:42:10Z", "session": 3, "by": "player:anna", "data": {"map": "maps/thornwick", "from": [4, 7], "to": [9, 7]}}
{"id": 42, "type": "item.gained", "entity": "pc/thalia", "day": 152, "time": 885, "real": "2026-11-07T19:55:02Z", "session": 3, "by": "dm", "data": {"item": "core:items/flame-tongue", "qty": 1, "from": "npc/mira"}}
{"id": 43, "type": "hp.changed", "entity": "monster/goblin-chief-1", "day": 152, "time": 890, "real": "2026-11-07T20:01:33Z", "session": 3, "by": "dm", "data": {"delta": -9, "hp": 12, "reason": "longsword"}}
{"id": 44, "type": "time.advanced", "entity": "", "day": 153, "time": 480, "real": "2026-11-07T21:30:00Z", "session": 3, "by": "dm", "data": {"from_day": 152, "from_time": 900, "reason": "long rest"}}
```

## Storage: one JSONL file per campaign

`<campaign folder>/events.jsonl`: one event per line, appended, never rewritten.

Why JSONL over SQLite:
- **No dependency.** Godot reads it with `FileAccess` + `JSON`. SQLite would need a GDExtension addon for every build.
- **Append-only by nature.** Writing an event is one appended line, and a crash loses at most that line.
- **Readable and diffable.** You can open it in an editor, back it up with git, and the MCP server (Python/TS) reads it in two lines of code.
- **Small.** Even a few thousand events per session stay a few MB over a whole campaign. The DM host loads the whole log into memory at start and keeps an index per entity and per day.
- **One log per campaign**, because each campaign has its own timeline. Worlds and core have no log; they change only through the vault.

Revisit when the log passes about 50 MB or startup replay gets slow. The fix then is snapshot files (state at day N) next to the log, not a switch to a database.

## MVP event types

| Type | `entity` | `data` |
| --- | --- | --- |
| `token.placed` | the entity | `map`, `at: [x, y]` |
| `token.moved` | the entity | `map`, `from`, `to`; `group` (party token id) when moved as a party, one event per member |
| `token.removed` | the entity | `map` |
| `hp.changed` | creature | `delta`, `hp` (after), `temp` (optional), `reason` |
| `item.gained` / `item.lost` | holder | `item` (entity id, `core:` prefix for core data), `qty`, `from` / `to` (optional) |
| `sheet.changed` | creature | `path` (dotted, e.g. `stats.str`, `ac`), `from`, `to`, `reason`. Any other sheet field. |
| `level.gained` | PC | `class`, `level` (new class level) |
| `entity.sent` | the new campaign copy | `source` (e.g. `core:5e-core-rules/monsters/goblin` = package/kind/id, `world:npc/mira`), `layer` |
| `time.advanced` | `""` | `from_day`, `from_time`, `reason`. The event's own `day`/`time` are the new clock. |
| `note.added` | entity or `""` | `note` (path of the session note), `text` (short summary) |
| `session.started` / `session.ended` | `""` | `{}`. `session` holds the number. |
| `dice.rolled` | roller | `roll` (e.g. `perception`), `formula`, `result`, `dice`. History only, changes no state. |

Later, not MVP: conditions, initiative, party split/merge, travel arrivals (`party.arrived`), drafts from assistants.

## Calendar

Events never store formatted dates. `calendars/<name>.json` defines months (with festival days), weekdays, eras and the format string. `WorldCalendar` (`scripts/timeline/calendar.gd`) turns `day` / `time` into text, e.g. day 0, 540 → *Moonday, 1. Deepwinter 1 AF, 09:00*. `calendars/default.json` is a placeholder (335 days, 7-day week) until our world's calendar exists. Test: `godot --headless --path . -s tools/test_calendar.gd`.

Not yet: leap years and moons (later, with the calendar editor).
