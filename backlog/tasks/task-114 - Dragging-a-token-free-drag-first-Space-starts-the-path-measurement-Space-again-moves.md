---
id: TASK-114
title: >-
  Dragging a token: free drag first, Space starts the path measurement, Space
  again moves
status: In Progress
assignee: []
created_date: '2026-11-05 00:47'
updated_date: '2026-11-05 00:50'
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
- [ ] #1 Dragging a token shows no path/trail/distance until Space is pressed
- [ ] #2 Space while dragging starts the measured path from the real token's position
- [ ] #3 The token only moves when Space is pressed again (planned move as before)
- [ ] #4 Esc cancels; several selected tokens work
- [ ] #5 Headless test for the drag states (free -> measuring -> planned -> moved)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Decided by Nico (2026-11-05):** letting go **without** Space (no path mode) moves the token **straight to the new position**: no planned move, no extra Space. For the event log / timeline, the move is saved as a **straight line** from start to end; the metres moved are the straight distance on the grid. Path mode (Space while dragging) works as described: measured path, planned move, Space moves.
<!-- SECTION:NOTES:END -->
