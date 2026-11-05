---
id: TASK-91
title: >-
  Panels: no Pop out / Dock buttons; popped-out windows borderless and dock back
  when dragged in
status: Done
assignee: []
created_date: '2026-11-04 12:59'
updated_date: '2026-11-04 13:17'
labels:
  - ui
  - docking
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-04:

**1. No buttons.** Remove the "Pop out" and "Dock" buttons from the panels (DockPanel: Compendium/Book, chat, sheets, ...). Dragging is enough:
- dragging a panel past the program's edge pops it out (exists);
- dragging it onto a dock zone docks it (exists).

**2. Popped-out windows don't dock back.** When a popped-out panel is dragged back over the program by its **Windows title bar**, nothing happens. The OS moves the window and Dragoon never sees a drag end. Two options:
- **(a) Catch it:** watch the popped-out `Window`'s position while the left mouse button is held (`NOTIFICATION_WM_POSITION_CHANGED` or polling `DisplayServer.mouse_get_button_state()`), and on release over the main window run the same `drop_at` as the in-app carry (`dock_panel.gd` `start_carry` / `carry_to` / `drop_at`).
- **(b) Remove the Windows frame (preferred, fits the slim no-head style):** popped-out windows become borderless (`Window.borderless = true`). They are moved by dragging their background, as docked panels already are (`start_carry`), which already docks them on release over the program. They need their own resize edges/corners, and maybe a small close cross.

Pick (b) unless something blocks it. Then the docking and undocking logic stays in one place.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No Pop out / Dock buttons left on any panel
- [x] #2 Dragging a panel out of the program pops it out, dragging it back over a dock zone docks it, also for a popped-out one
- [x] #3 Popped-out windows are borderless (or, if (a): a title-bar drag back over the program docks it)
- [x] #4 Popped-out windows can still be resized and closed
- [x] #5 Layout (docked/floating/popped out, sizes) is still remembered
- [x] #6 Popped-out windows have close, minimise and maximise/restore buttons at the top right
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Nico 2026-11-04 (decided): go with (b), borderless. Popped-out windows get their own **close, minimise and maximise buttons at the top right**, small and in Dragoon's style (e.g. TravelBook-like crosses):
- **minimise** = `Window.mode = MODE_MINIMIZED` (taskbar);
- **maximise** toggles maximised / restored on that window's screen, with the button switching to "restore";
- **close** hides the panel the same way the panel's own close does today.

Double-clicking the window's background could also toggle maximise (optional).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Done with option (b), borderless, as Nico decided. All in `scripts/ui/dock_panel.gd`.

- **No buttons:** the Pop out / Dock button is gone. Dragging a panel past the program's edge pops it out. Dragging it by its title back over the program docks it (the existing `start_carry` / `drop_at`, now the only way).
- **Borderless:** popped-out windows have `borderless = true`. Without the OS title bar there is nothing left that moves the window without docking.
- **Resize:** a 6 px border around the window resizes it through the OS (`Window.start_resize`), with fitting cursors (`window_edge`).
- **Window buttons:** `WindowButton`s for minimise, maximise/restore and close, drawn in the page's ink. Close turns red on hover. Maximise shows two squares while maximised.
  - They sit at the top right, in the head; for a panel without a head (the timeline bar) they sit over its corner.
  - Minimise puts the window on the taskbar. Maximise toggles maximised/restored on its screen.
  - Close works like before: it hides the panel, or docks it back (`close_window`).
- **Extras:** double click on the title toggles maximise. Dragging a maximised window restores it first.
- **Layout:** still remembered. The window rect is saved only while not maximised.

Checked with rendered screenshots of a popped-out Compendium-style panel and the timeline bar.

Tests: `test_minimal` has new checks (no Pop out/Dock buttons, borderless, the three buttons, resize edges, close button). `test_character_hud`, `test_timeline_bar` and `test_show_everyone` pass.

Commit 7b77074.
<!-- SECTION:FINAL_SUMMARY:END -->
