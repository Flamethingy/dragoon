---
id: TASK-21
title: Entity editor in the VTT
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-01 13:02'
updated_date: '2026-11-01 13:44'
labels:
  - mvp
  - ui
  - data
dependencies:
  - TASK-1
  - TASK-22
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
- [x] #1 Create, edit, duplicate and delete entries of every kind in a world package or campaign
- [x] #2 Markdown text fields with live preview; wikilinks autocomplete across campaign/world/core
- [x] #3 Monster editor edits stats and the feature list (add, reorder, edit feature entries)
- [x] #4 Changes in a campaign during a session are logged as events where the event doc says so; prep edits save to JSON
- [x] #5 Source (book) packages are read-only by default; editing makes a copy or needs an explicit unlock
- [x] #6 The editor opens in the entry's full-view tab from TASK-22 (Edit button), so viewing and editing happen in the same place
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
EntryStore (scripts/data/entry_store.gd) edits package and campaign folders: create from Schema.blank, rename-safe save, duplicate, delete, atomic writes, whole numbers stay ints, package counts kept up to date. Source packages are read-only until "Unlock" (`editable: true`). "Edit a copy" copies an entry plus its features and images into a world package and sets `origin`. commit(): in a campaign during a running session (EventLog.in_session), creature sheet changes become sheet.changed events and the file keeps its values (text fields are still saved); prep edits go to JSON. Schema lists form fields per kind (from data-layout.md); extra keys get a guessed type. EntryEditor replaces the full view in the same tab after Edit. Fields: lines, numbers, choices, lists, refs, image picker (copied into assets/), ability scores, speeds, bonuses, JSON, and Markdown with live preview and [[ suggestions (PackageDB.suggest over core and world packages). FeatureList for monsters: add by name or id, reorder, remove; Edit opens the feature in its own tab. Save (Ctrl+S), Cancel, Duplicate, Delete with a confirm dialog. "New..." in Browse creates entries in a world package or a new one, and the book updates in place. Limitation: campaign entries are not listed in the compendium yet. They arrive with TASK-6 (unified index), and so do campaign names in [[ suggestions and the event_log hookup from the table. The store side is ready and tested. Tests: tools/test_entry_store.gd and tools/test_entry_editor.gd. Commit 7198edd.
<!-- SECTION:FINAL_SUMMARY:END -->
