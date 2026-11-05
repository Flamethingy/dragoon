---
id: TASK-100
title: >-
  Close button for Book, Compendium and character sheets (like the popped-out
  window bar)
status: Done
assignee: []
created_date: '2026-11-04 14:44'
updated_date: '2026-11-04 14:46'
labels:
  - ui
  - panels
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-04: popped-out windows have their own close / minimise / maximise buttons at the top right since TASK-91. The **Book**, the **Compendium** and the **character sheets** need a way to close the same way while they are **inside** the program, docked or floating.

- A close button at the top right, in the same look as the popped-out window bar (TASK-91), so it looks the same docked and popped out.
- The sheet pages (1–9) and detached pages (TASK-92) too.
- Esc keeps working where it already does.
- Reopening (key or button) restores the last place and size.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Book, Compendium and character sheets have a close (X) at the top right when inside the app
- [x] #2 Same look as the TASK-91 window bar
- [x] #3 Reopening restores the last place/size
- [x] #4 Headless test: the X closes each of them
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 1c1f517.

- **DockPanel:** new `closable` property. It adds the TASK-91 `WindowButton` (kind "close", same drawing, hover red) at the right end of the head as `PanelClose`.
  - It shows while the panel is inside the program (docked left, right or bottom, or floating).
  - While popped out it's hidden, because the window's own min/max/close buttons sit there.
  - `close_panel()` hides the panel and emits `closed`, so the Dock hides it and keeps its place. Popped out, it does `close_window()`.
- **Book and Compendium:** `Dock.float_panel` sets `closable`. Reopening (button or Esc menu) brings them back where they were, e.g. docked left. That's the DockPanel place plus Dock's `wanted`.
- **Character sheet** (SheetPanel): the "Close" text button is now the same X.
- **Sheet pages:** the same X at the right end of the tab row; Esc and the number key still close them.
- **Detached pages** (TASK-92) already have the window bar.
- **Test:** `tools/test_close_buttons.gd`.
  - For Compendium and Book: the X is there at the top right; docked left, it closes; reopened, it's back on the left; popped out, the window buttons take over and the X comes back on dock-back; floating, the X closes it too.
  - The sheet and sheet-page X close them.
  - minimal, detached_pages, sheets, app, character_hud and compendium_back pass.
<!-- SECTION:FINAL_SUMMARY:END -->
