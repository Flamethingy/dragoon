---
id: TASK-93
title: >-
  Dragging entries from the Book: transparent card preview, turns into the token
  ghost over the map
status: Done
assignee: []
created_date: '2026-11-04 13:15'
updated_date: '2026-11-04 13:29'
labels:
  - ui
  - compendium
  - drag-and-drop
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-04: when dragging game elements (monsters, items, classes, spells, ...) from the Compendium/Book or any list of entries, a **transparent copy of the card** being dragged should follow the mouse, e.g. via `set_drag_preview` with the entry's card or list row at ~50–60% opacity, so it's clear what is being dragged and that a drag is happening.

**Over the map:** when the drag hovers over the map and the entry **can be spawned in the world** (creatures and characters as tokens; maybe items as a loot/object token if that exists), the card preview is **replaced by the transparent token ghost**: the existing spawn ghost `MovePlans.show_spawn` at the snapped cell, at the creature's size. The card preview is hidden meanwhile. Moving back off the map (over a panel) shows the card again.

Entries that can't be spawned (classes, features, rules text, ...) keep the card preview over the map. Optionally show a small "can't be placed here" hint or a not-allowed cursor.

Also for drags onto the HUD / sheet (e.g. an item onto a character), the card preview is enough.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Dragging any entry shows a semi-transparent copy of its card following the mouse
- [x] #2 Over the map, spawnable entries switch to the transparent token ghost at the snapped cell (right size); back over a panel the card shows again
- [x] #3 Non-spawnable entries keep the card preview over the map
- [x] #4 Dropping works exactly as before
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Already there: `scripts/app/map_drop.gd` shows the spawn ghost (`show_spawn`, `ghost_texture`) while dragging a creature over the map. What's missing is the transparent card preview while dragging (and hiding it while the ghost shows). Items, spells and features over a token (TASK-94) keep the card preview.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit cfad11c.

- **Card preview:** `EntryDrag.preview(e)` used to be a name label. It's now a real `EntryCard` of the entry at 55 % opacity (`PREVIEW_ALPHA`), centred on the mouse and ignoring the mouse. Every drag from a book card uses it (`EntryCard._get_drag_data`). `EntryDrag.preview_node()` and `show_preview(on)` reach it while the drag runs.
- **Over the map:** when `MapDrop` shows the spawn ghost (creatures and characters, DM, at the snapped cell and the creature's size, as in TASK-45), it hides the card. Off the grid, off the map (mouse exit), at drag end and after the drop, the card shows again.
- **Not spawnable** (spells, classes, features, …): the card stays. Items, spells and features over a token (TASK-94) keep the card and light up the token.
- **Dropping:** unchanged.
- **Test:** `tools/test_entry_preview.gd`.
  - The preview is the card, see-through and centred.
  - A real mouse drag from a book card shows it.
  - Over the map, a goblin hides the card and the ghost shows; leaving the map brings the card back.
  - A spell keeps its card.
  - Dropping a character still places the token, and the card isn't left hidden.
  - entry_drops, minimal, app, scene_prep, token_moves, compendium and compendium_tabs all pass.

Note: across OS windows, the preview stays in the window the drag started in. This is a Godot limitation, the same as before.
<!-- SECTION:FINAL_SUMMARY:END -->
