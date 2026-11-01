---
id: TASK-21
title: Entity editor in the VTT
status: To Do
assignee: []
created_date: '2026-11-01 13:02'
labels:
  - mvp
  - ui
  - data
dependencies:
  - TASK-1
documentation:
  - data-layout
  - package-format
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The VTT is the only editor now ([[data-layout]]). The DM needs to create and edit entries of every kind (PCs, NPCs, monsters, places, factions, items, maps, lore, notes) in packages and campaigns: form fields for structured data, a Markdown editor with live preview for text fields (the "Visible for" popup from TASK-19 plugs in here), image picking for tokens/portraits/maps, and features editable as their own entries.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Create, edit, duplicate and delete entries of every kind in a world package or campaign
- [ ] #2 Markdown text fields with live preview; wikilinks autocomplete across campaign/world/core
- [ ] #3 Monster editor edits stats and the feature list (add, reorder, edit feature entries)
- [ ] #4 Changes in a campaign during a session are logged as events where the event doc says so; prep edits save to JSON
- [ ] #5 Source (book) packages are read-only by default; editing makes a copy or needs an explicit unlock
<!-- AC:END -->
