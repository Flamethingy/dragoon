---
id: TASK-73
title: 'Rules P5 (later): vision, light, fog of war, difficult terrain'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:45'
updated_date: '2026-11-02 03:47'
labels:
  - map
  - phase-5
  - later
dependencies:
  - TASK-62
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A big feature, only after the core loop works.
- Walls/doors drawn on maps, token vision (darkvision etc. from senses) and light sources, fog of war per player.
- Difficult terrain painted on the grid, which doubles movement cost in the movement budget (TASK-62).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Walls and doors drawn on maps by the DM; doors open and close
- [x] #2 Token vision with light sources, map lighting and darkvision from senses
- [x] #3 Fog of war per player (seen now / seen before; hidden tokens not sent)
- [x] #4 Difficult terrain painted on the grid doubles movement cost in the budget
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices:
- Everything is per map and off by default: existing maps stay as they were (lighting "bright", no fog, no walls). The DM's "Map" menu has: Draw walls (click corners, chains; Esc / right click ends), Draw doors (two corners), Erase walls, Difficult terrain (click/drag toggles), Lights (click adds/removes a 6 m bright + 6 m dim light), Lighting bright/dim/dark, and Fog of war. Edits are saved into the world's map entry.
- Sight (Vision.visible): a square is seen if the line from the token's centre to it crosses no wall or closed door (a corner where walls meet blocks too), and it is lit (ambient, or within a light's bright/dim radius) or within darkvision (from senses "Darkvision 18 m" / "60 ft."). The cap is 40 squares. Dim counts as seen; the perception disadvantage is left to the table.
- Fog of war is computed on the host per player from their own tokens: black for never seen, dimmed for seen before (kept in table.json). Tokens outside a player's sight are not sent at all, and with fog on a move re-sends each player's view instead of the plain token_moved RPC (no position leaks). The DM always sees everything.
- Doors are events (door.toggled), so the log and undo work. The DM can open any door; a player only one within a square of their token. A far one is refused, since it's not their door to touch.
- Difficult terrain: each square entered costs one extra square in the turn budget (turn_usage) and on the move trail (MovePlans.extra_cost). It only warns, like the budget itself.
- Not done (later if wanted): one-way walls or windows, light from tokens (torches carried), per-creature hidden/invisible tokens, token-picture changes for Wild Shape.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
scripts/rules/vision.gd (Vision: blocking, crosses, line_clear, light_at, visible, path_cells, move_cost, terrain_of, darkvision_m). scripts/spikes/map_layer.gd (MapLayer: draws terrain, walls, doors, lights and fog; DM tools wall/door/erase/terrain/light; door clicks). TokenGrid.map_layer (input before tokens); MovePlans.extra_cost. NetTable: _map_sight in view_for (doors and terrain for all, walls and lights for the DM, fog/vision and token filtering per player), sight_of, explored (table.json), doors_open, toggle_door / request_door / _handle_door, edit_map, fog-aware moves, terrain in turn_usage. table_ui: Map menu (DM). Screenshots of the DM and fogged player views checked. Test: tools/test_vision.gd (55/55 green). Commit 503b053.
<!-- SECTION:FINAL_SUMMARY:END -->
