---
id: TASK-89
title: 'Bug: the black cursor on the timeline is gone, can''t look into the past'
status: Done
assignee: []
created_date: '2026-11-04 12:56'
updated_date: '2026-11-04 12:59'
labels:
  - timeline
  - bug
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-04: the black arrow (the cursor below the timeline line that you click or drag to look at a past moment, TASK-83) has disappeared. Looking into the past doesn't work any more.

Where to look:
- `scripts/ui/timeline_line.gd`: the "Looking back: a black one at the cursor" drawing around line 234, `_on_strip` / `drag_to` / `set_cursor`, input around lines 480–580;
- `timeline_bar.gd` `_on_cursor` → `cursor_changed` → TimelineSync / NetTable `looking_back`.

Recent commits on the bar and line could be the cause: the orange handle on top, no head, slim at the sides (b66d53f), hold to move the current time (d38b3f3, 3e88ba0), and the moons (9f54aa2). Maybe the strip's hit area or the drawing now sits outside the slim bar, or the orange-triangle drag swallows the clicks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Clicking/dragging on the line shows the black cursor and the table shows that past moment
- [x] #2 Double click / Home goes back to now
- [x] #3 Works docked horizontally and vertically
- [x] #4 A test covers clicking the line -> cursor_changed with a past time
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
I couldn't reproduce the bug in the running app (Nico's session at 2548x1320, as DM). A real mouse click on the line, including a click on a box while its tooltip was showing, set the black cursor, and the table looked back (looking_back was set and the map changed). Double click and Home still go back to now. No errors in the game log.

The black cursor was only a 9 px triangle under the line, among the tick dates, so it was easy to miss. It is now 30% bigger and has a 2 px hairline across the line (`timeline_line.gd` `_draw`).

New tests in `tools/test_timeline_bar.gd`:
- a click sends `cursor_changed` with a past time;
- a click next to the triangle moves it;
- Home goes back to now;
- docked vertically, a click looks back too.

All pass. Commit 2242868.

If it's still missing for Nico, we need the situation where it happens: player or DM, popped-out window, Show everyone, or during combat.
<!-- SECTION:FINAL_SUMMARY:END -->
