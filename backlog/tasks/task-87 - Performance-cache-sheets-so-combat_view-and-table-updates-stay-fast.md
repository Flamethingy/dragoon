---
id: TASK-87
title: 'Performance: cache sheets so combat_view and table updates stay fast'
status: Done
assignee:
  - '@Tamago'
created_date: '2026-11-04 11:23'
updated_date: '2026-11-04 11:41'
labels:
  - performance
  - combat
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Measured 2026-11-04 (example world, 4 combatants, 19 events, headless):
- `combat_view()` ≈ 30 ms, because every row runs `turn_usage()` ≈ 8 ms;
- `sheet_for()` ≈ 3.8 ms each, and `turn_usage` builds it up to 3× (directly, `_feature_list`, `_spent_recharges`); `_features()` ≈ 1 ms.

The drag lag is fixed (the trail no longer calls it per mouse move, commit dcbeaf5). But `combat_view()` still runs:
- on every table broadcast (`net_table.gd:288`, per player);
- in the combat tracker (`combat_tracker.gd:58/155`);
- in the HUD (`hud_widgets.gd:301`).

During a fight, every event therefore costs tens of ms, which grows with combatants and events. This is likely the "general" sluggishness Nico noticed.

**Idea**
- Memoize `sheet_for(player, ref)`. Key: player, ref, the event log's revision (count + last id + day/time) and a timeline/entry revision. Return copies, or document that callers mustn't mutate.
- Pass the sheet into `_feature_list` / `_spent_recharges` instead of building it again.
- Cache `_features()` until the compendium changes.
- `combat_view()` once per change, shared by the broadcast, tracker and HUD.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 combat_view() with 4 combatants under ~5 ms (headless measure)
- [x] #2 sheet_for is built at most once per creature per change
- [x] #3 No stale sheets: tests (turn_economy, vision, crowd, sheets) pass
- [x] #4 No noticeable hitch when events happen in a fight
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 3d94d18.

**How the cache works**
- `NetTable._memo_of(name, build)` caches `sheet_for`, `turn_usage`, `combat_view` (DM) and `_features`.
- The key is the event log's state (count, last id, undone, rewound, day/time, insert mode), the new `Timeline.revision` (world reload or promote, rules, info), `looking_back`, the peer and the process frame. The frame bounds anything untracked, e.g. packages.
- Callers get deep copies (`_features` read-only, no copy).

**Measured** with `tools/perf_combat.gd` (4 combatants):
- a move plus the combat view: 120 ms → 21 ms;
- `combat_view` / `turn_usage` / `sheet_for` again in the same state: about 0.01 ms (was 29 / 5 / 3 ms).

**Tests:** 62 of 63 pass. `test_concentration` also fails without this change (the HUD concentration piece and the confirm), so that's a separate, pre-existing issue.
<!-- SECTION:FINAL_SUMMARY:END -->
