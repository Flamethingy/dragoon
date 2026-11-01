---
id: TASK-17
title: Extend event types for more scenarios
status: Done
assignee: []
created_date: '2026-11-01 12:50'
updated_date: '2026-11-01 14:10'
labels:
  - events
dependencies: []
documentation:
  - doc-1
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The 13 MVP event types (doc-1 Event format) are only a starting set. Nico wants events for all kinds of scenarios. Collect what is missing as features land and add the types with their payloads to the event doc. Candidates already known: conditions (applied/removed), initiative / combat start-end, party split/merge, travel arrivals (`party.arrived`), assistant drafts, spell slots / resources used, rests, death saves, currency, relationships/faction standing, quest progress, weather.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Event doc lists the new types with entity and data fields
- [x] #2 Each new type has at least one example event
- [x] #3 Replaying the log rebuilds state for the new types (tests)
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
doc-1 now lists 19 new event types with entity/data fields and an example each. They cover conditions, combat/initiative/turns, resources, rests, death saves, currency, relationships, quests, party split/merge/arrived, weather and assistant drafts. Replay.entity_state rebuilds the per-entity state and the new Replay.world_state rebuilds combat, weather and party groups. Item events keep a sheet's own inventory list shape. The sheet shows conditions, death saves, used resources and coins. Test: tools/test_event_types.gd. Commit: 221edde. Still open in the doc: spells cast/concentration, XP, exhaustion, light/vision.
<!-- SECTION:FINAL_SUMMARY:END -->
