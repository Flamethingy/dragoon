---
id: TASK-35
title: 'Encounters: save combats and replay them'
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 15:52'
updated_date: '2026-11-01 16:32'
labels:
  - mvp
  - events
  - map
dependencies:
  - TASK-34
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico's idea: save whole combat encounters and replay them to find out what happened. Spec in timelines.md, "Maps and encounters".
- An encounter is a named range of events `{id, name, map, start_event, end_event, session, day, participants[]}` in `encounters.json`.
- It is created automatically from `combat.started`/`combat.ended`, and can be renamed and its range adjusted.
- **Replay** on its map:
  - Controls: play/pause, step per event or per round, speed.
  - Beside the map: the event list (moves, attacks, rolls, HP changes, conditions). Clicking an event jumps there.
  - Read-only.
- An encounter list per timeline (by session and in-world date) to open them.
- Later idea, not in this ticket: encounter templates (prepared monsters and positions).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Ending a combat saves an encounter automatically; it can be renamed and its range adjusted
- [x] #2 Replay shows tokens moving, HP and conditions changing on the map, with play/pause, step (event/round) and speed
- [x] #3 Event list beside the replay; clicking an event jumps to it
- [x] #4 Replay never writes events
- [x] #5 Encounter list per timeline
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Table (DM): Start combat / Next turn / End combat (combat.started with the creatures on the map, combat.turn, combat.ended). Encounters (scripts/timeline/encounters.gd) syncs finished combats into encounters.json {id, name, map, start_event, end_event, session, day, time, participants}; rename / set_range only touch that file. EncounterReplay rebuilds tokens, HP, conditions, round per step. App view "Encounters" (DM): list by session and in-world date, rename, range, Replay -> ReplayView (map in a SubViewport, play/pause, step ±event, ±round, speed 0.5-4x, event list: click jumps, creature HP/conditions line). Test tools/test_encounters.gd checks that replay writes nothing. Commit 0772ce4.
<!-- SECTION:FINAL_SUMMARY:END -->
