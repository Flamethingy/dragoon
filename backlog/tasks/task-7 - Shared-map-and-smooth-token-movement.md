---
id: TASK-7
title: Shared map and smooth token movement
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-01 11:17'
updated_date: '2026-11-01 12:37'
labels:
  - mvp
  - map
  - network
dependencies:
  - TASK-5
documentation:
  - Dragoon Concept
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MVP: a shared map with a grid loaded from an image; tokens move with smooth tweens. Players may move their own tokens, the DM may move anything. Maps and token art are sent once and cached on clients by file hash.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 DM picks a map image, all clients see it with the grid
- [x] #2 Token moves are tweened and snap to the grid
- [x] #3 Players can only move tokens they own; DM can move all
- [x] #4 Images are cached by hash and only resent when changed
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The DM picks the map in the top bar (show_map_to_all), and every client shows it with the grid (map frontmatter: image, grid size/offset, tokens, party_start). Claimed PCs come along to the party start, and token positions per map come from the event log. Moves glide (tween, 0.12 s per cell) and snap to the cell; the host validates them. Players may only drag their own PC: the UI blocks other tokens and the host refuses "not your token". The DM moves anything, and every move is logged as token.moved with by=player:<name>. Images: AssetCache hashes files with SHA-256 (recomputed only when the file changes). Clients ask only for hashes missing from their disk cache (user://cache/assets), get them in 48 KB chunks, and check the hash on arrival. Switching back to a known map downloads nothing. TokenGrid gained show_map/add_token_view/clear/can_drag, so it can be fed data instead of files. Tests: tools/test_net_table.gd.
<!-- SECTION:FINAL_SUMMARY:END -->
