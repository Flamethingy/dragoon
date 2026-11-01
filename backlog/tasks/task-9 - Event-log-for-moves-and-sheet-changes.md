---
id: TASK-9
title: Event log for moves and sheet changes
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-01 11:17'
updated_date: '2026-11-01 12:20'
labels:
  - mvp
  - events
dependencies:
  - TASK-2
documentation:
  - Dragoon Concept
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MVP: every token move and sheet change is appended to the campaign's event log from day one, with in-world day, real date and session number. Sheets are computed from events; rewind UI comes later.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Moves and sheet changes are appended as events (append-only)
- [x] #2 Each event has in-world day/time, real date and session number
- [x] #3 A sheet's current state can be rebuilt from its events
- [x] #4 Log survives restart and is loaded on host start
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
EventLog (scripts/timeline/event_log.gd): append-only JSONL per campaign in the doc-1 format, with a world clock (day, time, session) and load on open. Replay (scripts/timeline/replay.gd) rebuilds an entity's state (hp, sheet fields, items, levels, token position) from its campaign copy plus events up to a moment, honouring `undoes`. Headless test covers restart, rebuild, undo and rewind.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
- **`EventLog`** (`scripts/timeline/event_log.gd`): the append-only `events.jsonl` per campaign, in the doc-1 format.
  - Every event gets an id, type, entity, in-world day and time, real date (UTC), session, author and data. Each one is written to disk immediately.
  - The world clock (day, time, session) moves with `time.advanced` and `session.started`.
  - Helpers write the MVP types: move/place token, HP, sheet field, item gained/lost, time, session. `undo(id)` appends an `undoes` event.
  - Loading on open restores events, clock, session, undos and the next id. A damaged line is skipped with a warning.
- **`Replay`** (`scripts/timeline/replay.gd`) rebuilds an entity's state from its campaign copy plus its effective events up to any moment, in (day, time, id) order. It covers HP, dotted sheet paths, inventory, levels and token position; `tokens_on(map)` gives every token on a map. The base entity is never changed.
- **Test** (`tools/test_event_log.gd`) passes: restart, rebuild, undo, rewind, damaged line, ids continuing.
- **Host:** the DM host opens the log on start in TASK-5.
<!-- SECTION:FINAL_SUMMARY:END -->
