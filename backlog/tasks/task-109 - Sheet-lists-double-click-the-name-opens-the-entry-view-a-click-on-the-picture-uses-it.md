---
id: TASK-109
title: >-
  Sheet lists: double-click the name opens the entry view, a click on the
  picture uses it
status: Done
assignee: []
created_date: '2026-11-04 23:20'
updated_date: '2026-11-04 23:24'
labels:
  - sheets
  - hud
dependencies:
  - TASK-107
  - TASK-108
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-04: "It should open on a double click on the text of skill or item in a character editor... on icon click you can do use action".

In the Inventory / Spells / Features pieces (TASK-107), on the HUD and on the sheet pages:
- double-clicking the name / text opens the entry's view (TASK-108: fields, chips, On Use, text) in a small window;
- clicking the picture (icon) uses the item or casts the spell;
- a single click on the text does nothing any more.

Players get the view as they may see it: package entries are read locally, the timeline's own entries are asked from the host (NetTable.open_entry, reveals apply).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Clicking the icon in a list row or a card uses the item / casts the spell; clicking the text doesn't
- [x] #2 Double-clicking a row or card opens a window with the entry's view including On Use
- [x] #3 Features open their view too; players get timeline entries through the host
- [x] #4 Tests pass
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit bf81a9b.

- **SheetLists `_connect`:** in list rows and cards, a click on the picture uses the item / casts the spell (it lights up on hover, and its tooltip says "Use it" / "Cast it"). A single click on the text does nothing; a double-click on the row or card calls `CharacterHud.show_entry(ref)`. Features have no use action yet, so their picture isn't a button and they only open.
- **`CharacterHud.show_entry`** uses `NetTable.lookup_entry`, which reads spells and items from the timeline, the world or the packages (catalog_entry) and features by id, and returns a copy with `_kind` and `ref`.
  - Anything not found here: a player asks the host (`open_entry` → `entry_received`, reveals apply).
- **New `EntryWindow`:** a window over the table with the compendium's EntryView (chips, On Use, text) without the book's buttons. One window per entry; Esc or × closes it.
- **StatBlock** no longer lists `effects`, `effects_parsed` and `ref` as raw fields, since the On Use section shows them.
- **Tests:** test_sheet_lists extended (picture click uses, text click doesn't, double-click opens, features, the window). character_hud, sheets, detached_pages, compendium, entry_editor, app, net_table and on_use pass. A real-run screenshot checked the Potion of Healing window with its picture and On Use.
<!-- SECTION:FINAL_SUMMARY:END -->
