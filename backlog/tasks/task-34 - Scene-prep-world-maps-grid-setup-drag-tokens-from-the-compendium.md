---
id: TASK-34
title: 'Scene prep: world maps, grid setup, drag tokens from the compendium'
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 15:52'
updated_date: '2026-11-01 16:27'
labels:
  - mvp
  - map
dependencies:
  - TASK-33
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Maps belong to the world, and token positions and moves are events in the timeline (timelines.md).
- Add a map to the world: import an image, then line up the grid by dragging. Drag a cell to set the size and the offset; set metres per cell.
- Drag a monster, NPC or PC from the compendium onto the map to place a token (`token.placed`). Several of the same monster get numbered tokens (Goblin 1, Goblin 2) and their own HP.
- The same map shows different positions in different timelines.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A map image can be added to the world and its grid aligned by dragging
- [x] #2 Dragging a compendium entry onto the map places a token as an event in the current timeline
- [x] #3 Several tokens of one monster are numbered and tracked separately
- [x] #4 Two timelines of one world show their own token positions on the same map
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DM bar in the table: "New map..." (pick a picture) and "Grid..." open MapSetup: drag over one square to set cell size and offset, fine tune, metres per cell; saved into the world (assets/maps + maps.json). "Tokens" opens TokenPalette: monsters, NPCs, PCs of the books, this world and this timeline, dragged onto the map (MapDrop) -> NetTable.drop_token -> token.placed in the timeline. Monsters become numbered timeline copies (Timeline.token_entity: Goblin 1, Goblin 2, copy_of + copy_number) with their own HP; world/timeline NPCs and PCs are placed themselves (dropped again = moved). Positions per timeline via Replay. Also: tokens without a picture now get a placeholder (they were invisible before). Test: tools/test_scene_prep.gd. Commit bc79226. Note: the palette is a compendium list beside the map, not a drag out of the full Compendium view (that view covers the map).
<!-- SECTION:FINAL_SUMMARY:END -->
