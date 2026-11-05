---
id: TASK-114
title: >-
  Dragging a token: free drag first, Space starts the path measurement, Space
  again moves
status: Done
assignee: []
created_date: '2026-11-05 00:47'
updated_date: '2026-11-05 00:52'
labels:
  - map
  - tokens
  - movement
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-05: dragging a token should **not jump straight into path calculation**.

**New flow:**
1. **Start dragging:** the token (ghost) simply follows the mouse. No pathfinding, no dotted trail, no distance label, so it's cheap and calm.
2. **Press Space while dragging:** path measurement starts. The path is calculated from the **current position of the real token** on the board (not from where the ghost is held) to the cursor, with the trail, metres and colours as before (white → yellow → orange → red, TASK-87 cache).
3. **From then on as before:** let go and the ghost stays as a planned move; the token **only moves when Space is pressed again** (MovePlans: Space sends all plans).

Details:
- Let go without having pressed Space: also a planned move (ghost + trail calculated once on release), so nothing moves without Space. *(Nico: is that right, or should a free drag without Space move directly?)*
- Esc / right-click while dragging cancels as before.
- Several selected tokens: Space turns measurement on for all of them.
- Players see the same (only for their own tokens).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Dragging a token shows no path/trail/distance until Space is pressed
- [x] #2 Space while dragging starts the measured path from the real token's position
- [x] #3 The token only moves when Space is pressed again (planned move as before)
- [x] #4 Esc cancels; several selected tokens work
- [x] #5 Headless test for the drag states (free -> measuring -> planned -> moved)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Decided by Nico (2026-11-05):** letting go **without** Space (no path mode) moves the token **straight to the new position**: no planned move, no extra Space. For the event log / timeline, the move is saved as a **straight line** from start to end; the metres moved are the straight distance on the grid. Path mode (Space while dragging) works as described: measured path, planned move, Space moves.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 518b18a.

- **Free drag (MovePlans):** a drag starts free (`measure: false`). The ghost follows the mouse with no trail, no metres and no terrain/speed lookups. `drag_by` doesn't grow a path, and `_draw` skips unmeasured plans.
- **Space while dragging** (TokenGrid._input → `plans.start_measure()`):
  - every dragged ghost gets a trail from its **real token's cell** to the ghost (`extend`), plus the terrain and speed for the colours;
  - from then on it's as before: let go → planned move, Space → they go;
  - with several selected tokens, all of them are measured.
- **Let go without Space** (Nico's decision): `TokenGrid.move_free(ends)` drops the ghosts and asks for a straight move per token (`move_requested`, no glide trail). The host logs it as a straight line and the cost is the straight squares (`_move_cost` → `Vision.path_cells`). Groups use the same `plan_group_move` ends.
- **Esc while dragging:** `cancel_drag` drops the ghosts, and releasing afterwards moves nothing.
- A picked-up planned ghost stays measured.
- **Note:** a right-click while dragging still pans the map; it doesn't cancel the drag.
- **Tests:**
  - test_token_moves: free drag has no trail; Space measures all dragged tokens; planned then moved with Space; free drag moves straight with no plan or trail; Esc while dragging.
  - screenshot_table now measures its sample drag.
  - token_moves, tokens ("all good", then the crash on quit it already had), net_table, app, areas, vision, timelines, timeline_bar, token_look and entry_preview pass.
<!-- SECTION:FINAL_SUMMARY:END -->
