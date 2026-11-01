---
id: TASK-41
title: 'Token look: border, background, framed image, facing; Token editor'
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 19:14'
updated_date: '2026-11-01 19:18'
labels:
  - tokens
  - ui
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico, 2026-11-01. Every spawnable entity (monsters, PCs, NPCs) has a token:
- a coloured border circle
- the image in the middle
- a background colour behind it, for transparent images

A **Token** button next to **Edit** opens a token review with a live preview. There you can:
- move and zoom the reference image into the middle
- pick the border colour and the background colour
- set whether the picture faces left or right; the image is mirrored on the map depending on where the token looks
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Tokens on the map are drawn as a border ring, a background colour and the image clipped to the circle
- [x] #2 A Token button next to Edit opens the token editor (preview, drag/zoom the image, 2 colour pickers, faces left/right) and saves into the entry
- [x] #3 Defaults work for entries without token settings
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit c4948b0.
- TokenArt (scripts/app/token_art.gd) composes each token: a border ring, a background colour and the picture framed in the circle. Results are cached.
- The settings live in the entry as `token_style`: border, background, offset, zoom and faces. Defaults depend on the kind.
- A Token button next to Edit opens TokenEditor with:
  - a live preview
  - drag to move the picture, wheel or slider to zoom
  - two colour pickers
  - "the picture looks to the" right or left
- Saving goes through `store.commit` and refreshes the map (`NetTable.refresh_tokens`).
- Read-only source packages are locked, with a hint to import or copy first.
- Mirroring by facing comes with TASK-42.
- Tests: test_token_look; 30/30 suites pass.
<!-- SECTION:FINAL_SUMMARY:END -->
