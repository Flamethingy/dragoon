---
id: TASK-50
title: Chat as a dockable window; HUD editor inspector with multi-select
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:35'
updated_date: '2026-11-02 00:51'
labels:
  - ui
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico, 2026-11-02 00:34:
- **The chat in its own window**, with a docking system like in IDEs: drag the chat to dock it.
- **Instead of the "Round buttons" switch, an inspector on the right of the editor:** it shows what is selected. Pieces that support it get options to tick, e.g. round.
- **Pieces are selectable in edit mode:** Shift + left click selects several, so shared attributes can be changed at once.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The chat docks to the left, right or bottom edge, or floats snapped to the grid
- [x] #2 The chat pops out into its own OS window; closing that window docks it back
- [x] #3 The chat's place is saved per player and stays when the active character changes
- [x] #4 An inspector on the right of the editor shows the selected pieces' variant, round, size, name and badge options
- [x] #5 Shift + click and box select pick several pieces; the inspector changes their shared attributes, and dragging moves them together
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Mochi's plan:
- **Docking with the grid works:** the chat becomes a piece ("chat") on the 48×27 grid like the others.
  - Dragging it by its title bar shows dock zones: the left, right and bottom edges, highlighted while dragging. Dropping on a zone snaps it there.
  - Anywhere else it floats, snapped to whole cells. Resize from the edge.
  - "Pop out" sends it to its own OS window (Godot sub-window, e.g. on a second monitor). Closing that window docks it back.
- **Inspector** (right side of the edit mode, replacing the toggle). It shows the selection:
  - Variant
  - Round (quick buttons)
  - Size w×h and position
  - Show name, show amount badge
  - Spell, item or check (what a quick button points at)
  - With several pieces selected, only the shared attributes show; a mixed value is shown as "—".
- **Selection:**
  - Click selects one piece; Shift + click adds or removes one.
  - Drag on empty space draws a selection box.
  - Dragging a selected piece moves the whole selection.
  - Delete removes the selection.

Nico, 2026-11-02 00:35: the chat's place is per player. It stays where I put it, whichever character is active, so it is not part of the character's HUD layout. It is saved locally per user, in the user settings, not as an event.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 1ed2730.

**ChatBox**
- Drag it by the title to dock it left, right or at the bottom. Elsewhere it floats, snapped to the 48×27 grid.
- Resize from the inner edge or the corner.
- Pop out puts it in a native window; closing that window docks it back.
- Its place is saved per player in chat.cfg.

**LayoutEditor**
- Selection: click, Shift + click, box select; group move; Delete removes.
- The inspector on the right shows the variant, round, badge, name, size, position and the quick button's ref; values that differ show as "mixed".

Tests: test_character_hud extended; 33 suites pass.
<!-- SECTION:FINAL_SUMMARY:END -->
