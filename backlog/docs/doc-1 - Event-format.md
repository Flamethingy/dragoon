---
id: doc-1
title: Event format
type: specification
tags:
  - events
  - decision
project: Dragoon
created_date: '2026-11-01 11:41'
updated_date: '2026-11-01 14:09'
---

How the VTT records changes on the world timeline (concept: *Timeline and calendars*, [[Dragoon Concept]]). Result of [[TASK-2]].

**Status:** proposal by Mochi, 2026-11-01. MVP event types approved by Nico on 2026-11-01 as a starting set. They will be extended for many more scenarios later. The storage decision is still open for the group to confirm.

## The rule: event or entity?

- **Entity (JSON entry, edited in the VTT):** what something *is*: base stat block, lore, token art, size. Lives in a package (core or world) or, if created during play, as an `entity.created` event in the timeline (timelines.md).
- **Event (log, written by the VTT):** anything that *happens* during play or prep in the VTT: moving, gaining or losing things, damage, levels, time passing, notes.
- The state at a moment = the entry + all events up to that moment. The VTT never writes play state back into the entry files.

## Event record

One JSON object per event.

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | int | Sequence number in this campaign's log, starting at 1, never reused. |
| `type` | string | `area.verb`, e.g. `token.moved`. See the types below. |
| `entity` | string | Plain ref of the entity it is about, `<kind>/<id>` (e.g. `characters/mira`, `creatures/goblin-1`). Empty string for world-wide events such as `time.advanced`. |
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
{"id": 41, "type": "token.moved", "entity": "characters/thalia", "day": 152, "time": 870, "real": "2026-11-07T19:42:10Z", "session": 3, "by": "anna", "data": {"map": "maps/thornwick", "from": [4, 7], "to": [9, 7]}}
{"id": 42, "type": "item.gained", "entity": "characters/thalia", "day": 152, "time": 885, "real": "2026-11-07T19:55:02Z", "session": 3, "by": "dm", "data": {"item": "core:5e-core-rules/items/flame-tongue", "qty": 1, "from": "characters/mira"}}
{"id": 43, "type": "hp.changed", "entity": "creatures/goblin-chief-1", "day": 152, "time": 890, "real": "2026-11-07T20:01:33Z", "session": 3, "by": "dm", "data": {"delta": -9, "hp": 12, "reason": "longsword"}}
{"id": 44, "type": "time.advanced", "entity": "", "day": 153, "time": 480, "real": "2026-11-07T21:30:00Z", "session": 3, "by": "dm", "data": {"from_day": 152, "from_time": 900, "reason": "long rest"}}
```

## Storage: one JSONL file per timeline

`data/worlds/<world>/timelines/<timeline>/events.jsonl` (timelines.md, since TASK-32; it was one
file per campaign before): one event per line, appended, never rewritten. A forked timeline
starts with its parent's events up to the fork point (`fork_at`), which stay in the parent's
file; its own ids go on after them.

Why JSONL over SQLite:
- **No dependency.** Godot reads it with `FileAccess` + `JSON`. SQLite would need a GDExtension addon for every build.
- **Append-only by nature.** Writing an event is one appended line, and a crash loses at most that line.
- **Readable and diffable.** You can open it in an editor, back it up with git, and the MCP server (Python/TS) reads it in two lines of code.
- **Small.** Even a few thousand events per session stay a few MB over a whole campaign. The DM host loads the whole log into memory at start and keeps an index per entity and per day.
- **One log per timeline.** Worlds and core have no log; play never changes them.

Revisit when the log passes about 50 MB or startup replay gets slow. The fix then is snapshot files (state at day N) next to the log, not a switch to a database.

## MVP event types

| Type | `entity` | `data` |
| --- | --- | --- |
| `token.placed` | the entity | `map`, `at: [x, y]` |
| `token.moved` | the entity | `map`, `from`, `to`; `group` (party token id) when moved as a party, one event per member; `facing` (n, ne, e, se, s, sw, w, nw) where it looks after the step (TASK-42) |
| `token.turned` | the entity | `map`, `facing` (n, ne, e, se, s, sw, w, nw): turned on the spot (Shift + direction, TASK-42) |
| `token.removed` | the entity | `map` |
| `hp.changed` | creature | `delta`, `hp` (after), `temp` (optional), `reason` |
| `item.gained` / `item.lost` | holder | `item` (entity id, `core:` prefix for core data), `qty`, `from` / `to` (optional) |
| `sheet.changed` | creature | `path` (dotted, e.g. `stats.str`, `ac`), `from`, `to`, `reason`. Any other sheet field. |
| `level.gained` | PC | `class`, `level` (new class level) |
| `entity.created` | `<kind>/<id>` of the new entry | `entry` (the full entry). Something made during the timeline (a PC, an item given out, a new NPC); it exists in this timeline and its later forks (TASK-32). |
| `entity.edited` | the entry | `entry` (the full entry as it is now). A prep edit of a timeline entry, or a timeline's own version of a world entry. |
| `entity.deleted` | the entry | `{}`. A timeline entry removed. |
| `entity.promoted` | the entry | `world` (package id). The entry went into the world package; from then on the world's version counts. |
| `reveal.changed` | the entity whose text it is | `reveal` (id, e.g. `r7`), `field` (e.g. `description`), `add` / `remove` (lists of player ids, `party`, `dm`). See reveal-visibility.md. |
| `time.advanced` | `""` | `from_day`, `from_time`, `reason`. The event's own `day`/`time` are the new clock. |
| `note.added` | entity or `""` | `note` (path of the session note), `text` (short summary) |
| `session.started` / `session.ended` | `""` | `{}`. `session` holds the number. |
| `dice.rolled` | roller | `roll` (e.g. `perception`), `formula`, `result`, `dice`. History only, changes no state. |

`dice.rolled` at the table (TASK-12) also carries `results` (every roll of a multi-part roll such as attack + damage: `label`, `formula`, `total`, `dice`, `text`, `crit`), `who` (the creature's name) and `hidden` (a DM-only roll; never sent to players).

## More event types (TASK-17)

Added 2026-11-01 by Mochi. `Replay.entity_state` rebuilds the per-entity ones; `Replay.world_state(events)` rebuilds the world-wide ones: `{combat, weather, party_groups}`. Test: `tools/test_event_types.gd`.

| Type | `entity` | `data` | Replay |
| --- | --- | --- | --- |
| `condition.applied` / `condition.removed` | creature | `condition` (e.g. `poisoned`), `source` (optional), `until` (optional `{day, time}`) | `conditions` list |
| `combat.started` | `""` | `map`, `order: [{entity, initiative}]` (may be empty) | world: `combat` active, round 1 |
| `initiative.rolled` | combatant | `total`, `formula` (optional) | world: joins / re-sorts the order |
| `combat.turn` | `""` | `round`, `turn` (index into the order) | world: round and turn |
| `combat.ended` | `""` | `reason` (optional) | world: combat inactive |
| `resource.used` / `resource.restored` | creature | `resource` (dotted, e.g. `spell_slots.1`, `ki`, `second_wind`), `amount` (default 1; restored without amount = all) | `resources_used` {resource: n} |
| `rest.taken` | creature (one event per member) | `kind` (`short` / `long`), `hp` (after, optional), `restores` (short rest: resources it refills) | long: HP, clears resources, death saves, temp HP |
| `death_save.rolled` | creature | `success`, `roll`, `count` (2 for a natural 1), `hp` (a natural 20: back up with this HP) | `death_saves` {successes, failures}; cleared when HP > 0 |
| `currency.changed` | holder | `delta` ({gp, sp, cp, ep, pp}), `reason` | `currency` sums |
| `relationship.changed` | NPC or faction | `with` (entity or `party`), `from`, `to` (word or number), `reason` | `relations` {with: to} |
| `quest.updated` | quest | `status` (`open` / `done` / `failed`, optional), `step` + `text` (optional) | `quest_status`, `progress` list |
| `party.split` / `party.merged` | `""` | `groups: [[pc refs]]` / `place` (optional) | world: `party_groups` ([] = one party) |
| `party.arrived` | PC (one per member) | `place`, `map`, `at` | `location` |
| `weather.changed` | `""` | `region` (place ref, `""` = everywhere), `weather`, `temperature`, `wind` | world: `weather` per region |
| `assistant.drafted` | the entity drafted for | `assistant`, `field`, `text`, `status` (`draft` / `accepted` / `rejected`) | history only |

`item.gained` / `item.lost` keep the shape of a sheet's own inventory list (`[{item, qty, ...}]`) when the entity has one.

### Examples

```json
{"id": 51, "type": "condition.applied", "entity": "pcs/thalia", "day": 152, "time": 900, "real": "2026-11-07T20:10:00Z", "session": 3, "by": "dm", "data": {"condition": "poisoned", "source": "monsters/giant-spider"}}
{"id": 52, "type": "combat.started", "entity": "", "day": 152, "time": 900, "real": "2026-11-07T20:10:05Z", "session": 3, "by": "dm", "data": {"map": "maps/forest-road", "order": [{"entity": "monsters/goblin-chief", "initiative": 12}]}}
{"id": 53, "type": "initiative.rolled", "entity": "pcs/thalia", "day": 152, "time": 900, "real": "2026-11-07T20:10:09Z", "session": 3, "by": "anna", "data": {"total": 17, "formula": "1d20+3"}}
{"id": 54, "type": "combat.turn", "entity": "", "day": 152, "time": 901, "real": "2026-11-07T20:14:30Z", "session": 3, "by": "dm", "data": {"round": 2, "turn": 1}}
{"id": 55, "type": "combat.ended", "entity": "", "day": 152, "time": 903, "real": "2026-11-07T20:31:00Z", "session": 3, "by": "dm", "data": {"reason": "goblins fled"}}
{"id": 56, "type": "resource.used", "entity": "pcs/thalia", "day": 152, "time": 901, "real": "2026-11-07T20:15:00Z", "session": 3, "by": "anna", "data": {"resource": "spell_slots.1", "amount": 1}}
{"id": 57, "type": "resource.restored", "entity": "pcs/thalia", "day": 152, "time": 960, "real": "2026-11-07T20:40:00Z", "session": 3, "by": "dm", "data": {"resource": "second_wind"}}
{"id": 58, "type": "death_save.rolled", "entity": "pcs/thalia", "day": 152, "time": 902, "real": "2026-11-07T20:20:00Z", "session": 3, "by": "anna", "data": {"success": false, "roll": 1, "count": 2}}
{"id": 59, "type": "rest.taken", "entity": "pcs/thalia", "day": 153, "time": 480, "real": "2026-11-07T21:30:00Z", "session": 3, "by": "dm", "data": {"kind": "long", "hp": 24}}
{"id": 60, "type": "currency.changed", "entity": "pcs/thalia", "day": 153, "time": 500, "real": "2026-11-07T21:32:00Z", "session": 3, "by": "dm", "data": {"delta": {"gp": 15, "sp": -3}, "reason": "goblin loot"}}
{"id": 61, "type": "relationship.changed", "entity": "npcs/mira", "day": 153, "time": 520, "real": "2026-11-07T21:35:00Z", "session": 3, "by": "dm", "data": {"with": "pcs/thalia", "from": "neutral", "to": "friendly", "reason": "saved her brother"}}
{"id": 62, "type": "quest.updated", "entity": "quests/red-fang-road", "day": 153, "time": 520, "real": "2026-11-07T21:36:00Z", "session": 3, "by": "dm", "data": {"status": "open", "step": 2, "text": "Freed the prisoner"}}
{"id": 63, "type": "party.split", "entity": "", "day": 153, "time": 540, "real": "2026-11-07T21:40:00Z", "session": 3, "by": "dm", "data": {"groups": [["pcs/thalia"], ["pcs/aria", "pcs/borin"]]}}
{"id": 64, "type": "party.merged", "entity": "", "day": 153, "time": 700, "real": "2026-11-07T21:50:00Z", "session": 3, "by": "dm", "data": {"place": "places/thornwick"}}
{"id": 65, "type": "party.arrived", "entity": "pcs/thalia", "day": 153, "time": 700, "real": "2026-11-07T21:50:01Z", "session": 3, "by": "dm", "data": {"place": "places/thornwick", "map": "maps/westmarch", "at": [8, 6]}}
{"id": 66, "type": "weather.changed", "entity": "", "day": 153, "time": 720, "real": "2026-11-07T21:52:00Z", "session": 3, "by": "dm", "data": {"region": "places/westmarch", "weather": "heavy rain", "temperature": 9, "wind": "strong"}}
{"id": 67, "type": "assistant.drafted", "entity": "npcs/mira", "day": 153, "time": 720, "real": "2026-11-07T21:53:00Z", "session": 3, "by": "assistant:Tamago", "data": {"assistant": "Tamago", "field": "description", "text": "Mira's brother...", "status": "draft"}}
```

Still open (add as features land): spells cast / concentration, XP awarded, exhaustion levels, light sources / vision, encounter loot tables (TASK-25).

## Calendar

Events never store formatted dates. `calendars/<name>.json` defines months (with festival days), weekdays, eras and the format string. `WorldCalendar` (`scripts/timeline/calendar.gd`) turns `day` / `time` into text, e.g. day 0, 540 → *Moonday, 1. Deepwinter 1 AF, 09:00*. `calendars/default.json` is a placeholder (335 days, 7-day week) until our world's calendar exists. Test: `godot --headless --path . -s tools/test_calendar.gd`.

Not yet: leap years and moons (later, with the calendar editor).
