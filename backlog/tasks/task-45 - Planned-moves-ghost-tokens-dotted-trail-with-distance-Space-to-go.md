---
id: TASK-45
title: 'Planned moves: ghost tokens, dotted trail with distance, Space to go'
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 22:03'
updated_date: '2026-11-01 22:10'
labels:
  - tokens
  - ui
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico, 2026-11-01 22:03:
- **One ring that changes colour:** white = selected, orange = active.
- **Ghost previews:**
  - Dragging a token shows a transparent copy of it.
  - A token being spawned (dragged in from the Book or Compendium) shows a transparent preview under the mouse.
- **Planned movement** (drag only, not spawning):
  - The drag leaves a transparent dotted trail along the way the mouse took, showing the distance moved.
  - On release, a transparent token stays at the end. Nothing has moved yet.
  - **Space** moves the token there in a smooth glide along the trail. The dotted line disappears behind it on the way.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 80509a7.
- **MovePlans** (scripts/spikes/move_plans.gd), a child of TokenGrid:
  - Dragging leaves the real tokens where they are. Transparent ghosts follow the mouse, and the dotted trail adds one square at a time (diagonals first; going back shortens it). The distance shows as m, at 1.5 m per square.
  - On release the ghosts stay as plans. Group drags plan every selected token onto the closest free cells.
  - **Space** sends the planned moves: TokenGrid.go_planned → move_requested. Confirmed moves glide along the trail square by square, the dots vanish behind the token, and the plan disappears on arrival.
  - **Esc** drops the plans. A WASD step replaces a token's plan.
- **Spawn ghost:** MapDrop shows a transparent token on the hovered cell while a creature or character is dragged in from the Book.
- **One ring:** white = selected, orange = active.
- Tested in test_token_moves. All 33 suites pass.
- Not yet: other players see a straight glide (the trail is not sent with the move).
<!-- SECTION:FINAL_SUMMARY:END -->
