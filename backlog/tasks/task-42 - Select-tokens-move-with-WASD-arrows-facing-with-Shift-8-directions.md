---
id: TASK-42
title: 'Select tokens, move with WASD/arrows, facing with Shift, 8 directions'
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 19:14'
updated_date: '2026-11-01 19:22'
labels:
  - tokens
  - table
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico, 2026-11-01:
- Left click selects a token; dragging a box selects several.
- WASD or the arrow keys move the selected tokens one cell. Diagonals: two keys together (W+D...).
- A small triangle on the token's edge shows where the character looks, in 8 directions.
- Moving turns the token to face that way. Shift plus a direction only turns it.
- The image is mirrored when the token looks to the other side than the picture faces.
- Moves and turns go through the table as events, so they are synced and replayable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Click and box selection of tokens (only tokens you may move)
- [x] #2 WASD/arrows move the selection one cell, two keys at once move diagonally
- [x] #3 A triangle shows the facing in 8 directions; Shift+direction only turns
- [x] #4 Image mirrored by facing; moves/turns are events synced to players
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit bb80029.
- **Selecting:** click selects a token; Shift/Ctrl adds. A drag on the empty map draws a box. A click on the empty map clears the selection. Only tokens you may move can be selected.
- **Moving:** WASD/arrows step the selection one cell. Keys pressed within 70 ms combine into a diagonal; held keys repeat. Front tokens move first.
- **Facing:** moving turns the token. Shift + direction only turns it (new event `token.turned` {map, facing}). `token.moved` carries `facing`.
- **Look:** TokenMarks draws the facing triangle (8 directions) and the selection ring. The picture is mirrored by facing vs `token_style.faces`.
- **Sync and replay:** facings come from the events (`Replay.facings_on`), also in encounter replays and the event views. Players ask the DM (`request_step`), same as for moves.
- **Docs:** the event format doc has the new type.
- **Tests:** test_token_moves; 31/31 suites pass.
<!-- SECTION:FINAL_SUMMARY:END -->
