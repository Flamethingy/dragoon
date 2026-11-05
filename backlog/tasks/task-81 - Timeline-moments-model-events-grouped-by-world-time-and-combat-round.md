---
id: TASK-81
title: 'Timeline: moments model (events grouped by world time and combat round)'
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-02 13:31'
updated_date: '2026-11-02 13:34'
labels:
  - timeline
  - feature
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Foundation for the timeline bar (Nico 2026-11-02, sketch: a line with event boxes at the top of the table).

The event log is grouped into **moments**, and each moment becomes one box on the bar:
- everything that happened between two clock advances is one moment (`time.advanced` and the clock stamped on every event);
- in combat, each **round** is its own moment;
- a moment has its in-world start (day + minute, through the timeline's WorldCalendar), the map(s) it happened on, the entities involved, and a **summary of what changed** for the hover (e.g. "Borin moved 6 squares, took 7 damage; Goblin 2 died; +1 Potion"), built from the effective events (undone ones are left out);
- **session start/end** come from the real-world datetime of the session events and are marked on the line.

Map-independent: one timeline for all maps, so two fights on two maps at the same time stay visible together.

Later (not now): a "zoom out" that merges several rounds/moments into one summed-up box.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Moments are built from the effective events: one per stretch between clock advances, one per combat round
- [x] #2 Each moment has in-world start/end, its maps, its entities and a readable change summary
- [x] #3 Session start/end markers with their real-world datetime
- [x] #4 Undone events don't show; updates incrementally when new events arrive
- [x] #5 Headless test covers grouping, rounds, summaries and sessions
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 6da665b: new `TimelineMoments` (scripts/timeline/moments.gd). It only reads events.

- `build(log.effective(), hours_per_day, name_of)` groups the effective events (undone ones are already left out) into moments. A new moment starts when the world clock moves on (`time.advanced` or a later stamp), each combat round is its own moment (combat.started, or combat.turn with a new round), and what comes after combat.ended is a new moment.
- Each moment has `at` (in-world seconds since day 0; rounds that share a minute follow 6 s apart, and later moments of the same minute too, so the bar can space them by time), day/time, round, combat, maps, entities, event ids and `lines`, a summary for the hover. World lines come first ("2 hours pass (walk to the camp)", "Combat starts", "Round 2", "Combat ends"), then one line per entity ("Borin: appears, moves 3 squares, +2 Potion of healing", "Goblin 1: takes 7 damage, drops to 0 HP"). Dice, chat and initiative events belong to a moment but stay out of the summary.
- `sessions`: start and end markers with the real-world time and their place on the line.
- `add(e)` adds live events at the end. After an undo, the bar rebuilds from `effective()`. `moment_at(seconds)` and `moment_of_event(id)` support the bar and scrubbing.
- Test: tools/test_moments.gd (grouping, rounds, the 6 s spacing, summaries, an undone hit left out, sessions, live additions). It passes.
<!-- SECTION:FINAL_SUMMARY:END -->
