---
id: TASK-47
title: 'HUD editor (F2): per-character custom HUD on a screen grid'
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 22:24'
updated_date: '2026-11-01 22:43'
labels:
  - ui
  - sheet
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico, 2026-11-01 22:24:
- **HUD customisation per character.**
- **F2** starts edit mode: a grid over the screen, with the rest blurred for clarity.
- A **toolkit** to put together a custom-tailored HUD.
- **Resizable elements**, e.g. different panel layouts for the skill checks, or a bigger portrait.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Mochi's proposal:
- **Elements (widgets):**
  - Portrait
  - HP bar
  - Spell slots
  - Abilities
  - Saves
  - Skills
  - Single check buttons (e.g. only Perception)
  - Chat
  - Later: hotbar or action slots
- **Each element:** a rect on the screen grid (cells), snapped and resizable from its corners. Its contents rearrange to the size (e.g. skills in 1, 2 or 3 columns).
- **Edit mode (F2):**
  - The map is blurred and dimmed, and a grid is drawn over it.
  - The toolkit on one side lists the elements: drag one in, drag it to move, drag a corner to resize, Delete or right-click to remove.
  - F2 or Esc saves and leaves; "Reset to default" is available.
- **Layout data:** {element: {rect: [x, y, w, h] in grid cells, options}}. The grid is relative to the screen (e.g. 48×27 cells), so layouts survive other resolutions.

Open questions:
- Where is a layout saved?
  - In the character (all owners share it, it travels with the character)?
  - Or per player and character on this machine?
- What do creatures and the DM's tokens get: a default layout, or one per kind?

Nico, 2026-11-01 22:25: the layout is saved **in the character**, so every owner sees the same HUD. Plan: a `hud` field in the entity, changed as a sheet.changed event like other sheet edits. Only owners and the DM may edit it.

Nico, 2026-11-01 22:28: creatures get **one HUD per creature, from its template in the Book** (the world entry the copies come from, `copy_of`). The DM customises it once and every copy (goblin 1–5) uses it. Editing on a copy saves to the world entry, the same way token_style is inherited (Timeline.token_view). Without a layout: the default HUD.

Nico, 2026-11-01 22:35:
- Default HUD without a layout: **portrait, health and spell slots**.
- Extension: the **whole character sheet is customisable**. F3 opens a page editor like Android home screens, a grid filled with the same elements. **Keys 1–9** open the pages.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 9973bf6.
- **HudWidgets** (scripts/hud/hud_widgets.gd) builds each piece for its pixel size: portrait (+name), health, spell slots, info, abilities, saves, skills, description, features, spells, inventory. The check panels adapt their columns to the width, and a click rolls into the chat.
- **Layouts:** `[{w, r: [x, y, w, h]}]` in cells.
  - The HUD is on a 48×27 screen grid. Default: portrait, health and spell slots, lower left.
  - Sheet pages are 16×10 grids: `[{name, items}]`, up to 9. Defaults: "Sheet" and "Spells & gear".
- **LayoutEditor** (F2 / F3): the screen is blurred and dimmed under a grid, with a toolkit on the right.
  - Click adds a piece at the first free place; drag moves it, the corner resizes it, right-click removes it.
  - Reset to default, Cancel and Done. In page mode there are page tabs plus "+ Page" and "Delete page".
  - F2 / F3 / Esc save and close.
- **SheetPages:** keys 1–9 open page n (the same key closes it), centred like a book, with tabs.
- **Saving:**
  - NetTable.save_layout / _handle_layout saves to the character as a sheet.changed event (`hud`, `sheet_pages`). Owners and the DM may do this.
  - A creature copy saves into its template in the world package (`layout_template` via copy_of). Only the DM may, and every open copy refreshes.
  - sheet_for sends `_hud` / `_pages`.
- Tests: test_character_hud (default HUD, page keys, F2 add/move/remove/save, F3 new page, creature template shared, players denied). Screenshots: tools/screenshot_hud.gd. All 33 suites pass.
- Later: single-check pieces (e.g. just Perception), the chat as a piece, hotbar/actions, renaming pages.
<!-- SECTION:FINAL_SUMMARY:END -->
