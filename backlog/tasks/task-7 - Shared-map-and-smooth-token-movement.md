---
id: TASK-7
title: Shared map and smooth token movement
status: To Do
assignee: []
created_date: '2026-11-01 11:17'
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
- [ ] #1 DM picks a map image, all clients see it with the grid
- [ ] #2 Token moves are tweened and snap to the grid
- [ ] #3 Players can only move tokens they own; DM can move all
- [ ] #4 Images are cached by hash and only resent when changed
<!-- AC:END -->
