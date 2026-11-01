---
id: TASK-39
title: 'Compendium is core only: no kind re-pick, no world/timeline selection'
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 17:01'
updated_date: '2026-11-01 17:22'
labels:
  - compendium
  - ui
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **New entry from an overview:** clicking "New" in the Monster overview creates a monster straight away. Only ask for the kind when there's no kind context (e.g. the general "New" button).
- **The compendium is the top layer** (books and source packages). It has no world or timeline selection anymore, and new entries go into a package.
- World editing (NPCs, places, maps, factions, lore) happens only in the world view. Timeline entries (new items or NPCs during play, PCs) are made only in the timeline view.
- Those views can still use the compendium as a book (drag in, TASK-37).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 New from a kind overview creates that kind without asking
- [x] #2 No world/timeline selection anywhere in the compendium; it only edits packages
- [x] #3 World and timeline entries are created and edited in their own views
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Compendium.scope(): core (default; PackageDB.world_filter = "" so no world packages are read; new entries go into unlocked source packages, or a new "Homebrew" package via new_package), world (world_dir: core plus that world; new entries go into the world) or timeline (timeline_dir: core plus its world and timeline; new entries go into the timeline, Promote to world stays). The timeline picker is gone; the side bar shows what the book is. "New..." in a kind overview creates that kind right away (new_entry(kind)); on Packages and Drafts it asks for kind and target. App session views are now Table / Compendium (core) / World / Timeline (books) / Events (former event list) / Notes / Encounters. Edit world on the start screen opens the world's book. Imports into a "new package" make an editable source package instead of a world. Tests updated, plus checks for new-from-overview and no picker. Commit: see git log (after 40205c2).
<!-- SECTION:FINAL_SUMMARY:END -->
