---
id: TASK-104
title: >-
  Quick search: a hotkey popup to find items, spells, creatures and more from
  anywhere
status: Done
assignee: []
created_date: '2026-11-04 17:42'
updated_date: '2026-11-05 01:08'
labels:
  - ui
  - compendium
  - search
dependencies: []
priority: medium
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-04: a quick search for items and other entries, without opening the Compendium first.

- **A hotkey** (e.g. Ctrl+K or Ctrl+Space, plus a small 🔍 button) opens a search field in the middle of the screen, like a command palette.
- **Search as you type** across all kinds: items, spells, creatures, features, classes, rules / conditions, plus characters and places of the world.
  - fuzzy matching; results grouped by kind, with an icon and source;
  - arrow keys plus Enter;
  - the existing index can help (`PackageDB.suggest` / the unified index).
- **Filters** with prefixes, e.g. `i:` items, `s:` spells, `c:` creatures, or kind chips.
- **Results:**
  - **Enter** opens the entry (card / Compendium tab);
  - results can be **dragged** straight onto the map / a token / a sheet (TASK-93 / 94);
  - **Shift+Enter** adds it to the active character (same rights as TASK-94).
- **Respects reveal and drafts:** players only find what they are allowed to see.
- Esc or a click outside closes it. The last searches are remembered.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Hotkey opens a search popup anywhere at the table; Esc closes it
- [x] #2 Typing finds entries of all kinds (fuzzy), grouped, keyboard-navigable
- [x] #3 Enter opens the entry; dragging a result works like dragging from the Book
- [x] #4 Players only see revealed, non-draft entries
- [x] #5 Headless test: query returns expected entries and respects reveal
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 3539207.

**New `scripts/ui/quick_search.gd` (QuickSearch)**, an overlay at the table:
- **Opening:** Ctrl+K (pressed again, or Esc, or a click outside closes it) or the new 🔍 button next to Compendium, shown for everyone.
- **Search as you type:**
  - scores: exact, then start, then word start, then inside, then fuzzy (letters in order, fewer gaps first);
  - at most 8 results per kind, grouped by kind (the kind of the best match first), with a kind icon and the source;
  - prefixes filter: `i:` items, `s:` spells, `c:` creatures, `f:` features, `cl:` classes, `r:` rules, `co:` conditions, `ch:` characters, `p:` places, `ft:` feats, `rc:` races, `t:` tables;
  - ↑/↓ and the mouse select.
- **Results:**
  - Enter or a click opens the entry's view in an EntryWindow (TASK-109); a player's world entries come through `hud.show_entry` from the host, with reveals applied;
  - Shift+Enter gives it to the active character (`can_take_entry` / `add_entry_to`, the rights of TASK-94);
  - dragging a result works like a Book card (`EntryDrag` data, preview, start), and the search closes so the map or sheets under it take the drop.
- **Index:**
  - the core packages through its own PackageDB, loaded in the background (17,545 entries in about 0.5 s; a search takes about 18 ms);
  - the DM also gets `timeline.entries()` of the world and timeline kinds, without drafts;
  - a player asks the host (`NetTable.request_quick_index` → `quick_index_for(player)` → `quick_index_received`): no drafts, and a name inside a `<reveal>` only once that player may see it, with the tags stripped.
- **Recent searches:** the last 8, in `user://quick_search.cfg`, shown while the field is empty.
- **Test:** `tools/test_quick_search.gd` covers parse/score/grouping/prefix/fuzzy; the popup (Ctrl+K, typing, arrows, Enter opens a window, recent, Esc, dragging); and the DM's and player's index (hidden name, draft) over the network. app, net_table, character_hud, sheet_lists and detached_pages pass.
<!-- SECTION:FINAL_SUMMARY:END -->
