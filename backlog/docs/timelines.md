# Worlds and timelines (replaces campaigns)

Decided by Nico on 2026-11-01. Our two running campaigns play in the same world, so a separate
campaign copy of the world is not needed. Instead, a world has **timelines**: each is one history
of play, recorded as events on top of the world. This replaces the "campaign" layer of
data-layout.md, and "send into campaign" goes away.

## Layers

| Layer | Holds |
| --- | --- |
| Core | source packages (books), unchanged |
| World | world package: NPCs, places, factions, items, lore, **maps**, calendar |
| Timeline | one history in a world: players, events, notes, encounters |

## Folder

```text
data/worlds/<world-id>/
  package.json  npcs.json places.json maps.json items.json ...   (the world package, as before)
  assets/
  timelines/<timeline-id>/
    timeline.json   name, players [{id, name, color}], dm {name, color}, parent, fork_at, next_session, created
    events.jsonl    everything that happens in this timeline
    notes.json      session notes
    encounters.json saved encounters (below)
```

## How it works, like git

- **The world is the base.** A timeline never edits world files. The state of anything at a
  moment = world entry + this timeline's events up to that moment (as before with campaigns).
- **Start timeline.** Creating a world also creates its start timeline ("Prologue"). Prep that
  belongs to everyone (e.g. the state at the start of the story) goes there.
- **Fork.** A new timeline forks from another at an event (`parent`, `fork_at` = event id): it
  shares all events up to that point and has its own after it. Campaign A and B = two forks of the
  start timeline. Later forks are possible too ("what if" or a one-shot from session 12).
- **New things are commits.** Creating an entry during a timeline (a new item given to a PC, a new
  NPC, a PC itself) is an `entity.created` event with the full entry. It exists only in that
  timeline and its later forks. Changes are events as before (`sheet.changed`, `item.gained` ...).
- **Promote (merge into the world).** An entry created in a timeline can be promoted into the world
  package with one click, so other timelines can use it too. Ref and id stay the same.
- **PCs** live in their timeline (created by `entity.created`).
- **Refs:** `"<kind>/<id>"` resolves timeline-created entries → world → core.

## Maps and encounters

- Maps belong to the world. Token placement and movement are events in the timeline (as now),
  so the same map shows different positions in different timelines.
- **Encounter** (`encounters.json`): a named range of events in the timeline
  `{id, name, map, start_event, end_event, session, day, participants[]}`. It is created
  automatically from `combat.started`/`combat.ended` and can be renamed or adjusted.
- **Replay:** an encounter can be played back on its map: play/pause, step per event or per
  round, a speed control and the event list beside it (who moved, attacked, lost HP). Replay only
  reads events and never changes anything.
- **Encounter templates** (prepared monsters and positions to drop onto a map) are a later idea.

## Migration

`data/campaigns/<id>` (the example red-fang) becomes a timeline of its world (westmarch).
Campaign entries that were "sent" copies become plain refs to the world/core entry, plus
`entity.created` events for entries made in the campaign.
