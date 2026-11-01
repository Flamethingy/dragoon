---
id: TASK-37
title: Split and detach windows; compendium as a separate book
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 17:00'
updated_date: '2026-11-01 17:38'
labels:
  - ui
  - mvp
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico: the VTT needs decluttering. Practically any view should be splittable and detachable from the main window.
- **Views as panels:** table, compendium, notes, timeline, sheets, roll log, encounter replay.
  - Each panel can be docked (split left, right or bottom, with a draggable divider), shown as a tab, or **detached** into its own OS window (Godot multi-window, `Window` with `embed_subwindows = false`).
  - A detached window can be docked back.
- **Compendium = an extra book.** It always opens as its own window or panel and never covers the table. Entries can be dragged out of it wherever it makes sense:
  - onto the map → token (replaces the TokenPalette workaround from TASK-34)
  - into a sheet → item, spell or feature
  - into a note → link
  - onto a timeline → entity.created
- The layout (docked/detached, sizes, window positions per monitor) is saved per user in `user://` and restored.
- Players get the same for their views (table, notes, sheet).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Views can be split/docked with draggable dividers, tabbed, and detached into separate OS windows and docked back
- [x] #2 The compendium opens as its own book window or panel and never covers the map
- [x] #3 Drag from the compendium onto the map places a token; into a sheet adds the item/spell; into a note inserts a link
- [x] #4 Layout and window positions are restored on the next start
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit a4c74f5.
- **Dock** (scripts/app/dock.gd): every view is a panel docked left/right/bottom as tabs (tabs drag between areas, grips resize, tab menu: dock left/right/bottom, own window, close) or detached into a native OS window (force_native); closing the window docks it back. Sizes, places, open panels and window rects/screens are kept in user://layout.json and restored after hosting/joining.
- **App**: the table always stays in the middle; the bar toggles panels (Table = put the docked ones away). Panels: Session (notes + rolls), Sheet, Compendium (own window by default), World, Timeline books, Events, Notes, Encounters. Players get Session, Sheet, Notes.
- **Drag & drop** (EntryDrag): compendium cards onto the map → token (MapDrop, replaces the TokenPalette, which is gone); onto a sheet → inventory/spells/features via sheet.changed; into the session note box → [[kind/id|Name]] link; onto the timeline's book → entity.created in the live log; onto the world's book → copy into the world.
- Tests: new test_dock, extended test_app (panels, sheet panel, timeline drop), 28/28 suites green. Screenshot tool: tools/screenshot_dock.gd.
- Not verified by hand: dragging *between* OS windows (e.g. from the detached compendium window onto the map) can't be tested headless — worth trying first in the joint session.
<!-- SECTION:FINAL_SUMMARY:END -->
