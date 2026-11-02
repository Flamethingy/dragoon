---
id: TASK-78
title: F2 = edit mode toggle for desktop and pages 1-9 alike
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 01:16'
updated_date: '2026-11-02 08:43'
labels:
  - hud
  - ui
  - feedback
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico's feedback 2026-11-02: the normal HUD and the 1-9 pages are almost identical now. Unify them: F2 only turns edit mode on and off, whether you are on the desktop HUD or a page. Pressing 1-9 while in edit mode switches straight to editing that page (and back to the desktop HUD the same way).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 F2 toggles edit mode on the desktop HUD and on any page
- [x] #2 1-9 in edit mode switches to editing that page right away
- [x] #3 One shared editor for HUD and pages; layouts are saved as before
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices:
- F2 opens one editor for everything: set 0 is the HUD (tab "HUD": the screen behind it, shown smaller, on the HUD grid), then sheet pages 1-n (on paper, on the page grid). It starts on the page that is open, otherwise on the HUD.
- In edit mode, 1-9 switch straight to editing that page. The same key again goes back to the HUD (Nico: "back to the desktop HUD the same way"). The tabs "HUD 1 2 ..." do the same by mouse. Behind the editor, the page being edited opens; on the HUD tab, the pages close.
- F2 or Esc ends edit mode and saves. Cancel drops everything.
- Saving as before: the HUD into `hud` and the pages into `sheet_pages`. Only what actually changed is saved (no empty layout events).
- Reset on the HUD tab restores the default HUD; on a page tab it restores the default pages. "+ Page" and "Delete page" only work on pages (at most 9; the HUD can't be deleted).
- edit_hud() and edit_pages() remain as shortcuts into the same editor (open_editor(at)).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 56ada74. LayoutEditor: per-set grid/canvas/backdrop (_take_set), is_home/home/pages, show_page (1-9 toggles back to the HUD), set_shown signal, the Paper always present and shown per set, tabs "HUD 1 2 …", reset/add_page/delete_page aware of the HUD set. CharacterHud: open_editor(at) builds HUD + pages in one editor; _input routes 1-9 to the editor in edit mode; _show_behind opens or closes the page; saves only changed layouts. Checks added to test_character_hud. Screenshots of both views checked. Tests: 57/57 green.
<!-- SECTION:FINAL_SUMMARY:END -->
