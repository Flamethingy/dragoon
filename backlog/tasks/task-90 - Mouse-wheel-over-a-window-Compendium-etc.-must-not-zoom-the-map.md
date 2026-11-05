---
id: TASK-90
title: Mouse wheel over a window (Compendium etc.) must not zoom the map
status: Done
assignee: []
created_date: '2026-11-04 12:57'
updated_date: '2026-11-04 13:15'
labels:
  - ui
  - bug
  - input
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-04: scrolling in the Compendium, or in any other window or panel, also scrolls or zooms the map underneath. Only what's under the mouse (the focused window) should react.

Where to look: `TokenGrid._unhandled_input` zooms on `MOUSE_BUTTON_WHEEL_UP/DOWN` (scripts/spikes/token_grid.gd ~747).

Likely causes:
- a ScrollContainer that is already at its end, or a RichTextLabel / ItemList, lets the wheel event through as unhandled;
- panels with `mouse_filter = PASS` / `IGNORE`;
- floating / popped-out windows (DockPanel, separate `Window`s) forwarding their input to the main viewport.

Fix idea: the map only zooms when the mouse is over the map itself, i.e. no Control under the mouse (`get_viewport().gui_get_hovered_control()` is null or is the map's own canvas), and the event comes from the main window. Or mark wheel events over panels as handled, e.g. in DockPanel / the window base: `accept_event()` on wheel.

Applies to all windows: the Compendium/Book, sheets, chat, the timeline bar, the HUD, the tracker, dialogs, and popped-out windows.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Scrolling over the Compendium (docked, floating, popped out) never zooms or pans the map, also when its list is at the top/bottom
- [x] #2 Same for chat, sheets, timeline bar, HUD, tracker and dialogs
- [x] #3 Scrolling over the free map still zooms as before
- [x] #4 A headless test sends a wheel event over a panel and checks the camera zoom is unchanged
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Cause: Godot passes scroll events on from controls that can't scroll any further (`mouse_force_pass_scroll_events`, and ScrollContainer is MOUSE_FILTER_PASS). The wheel then reached `TokenGrid._unhandled_input` and zoomed the map.

Fix: `TokenGrid.over_ui()` checks `get_viewport().gui_get_hovered_control()`. Wheel events (up/down/left/right) are ignored whenever a Control is under the mouse. This covers every panel and window in the main window at once: Compendium, chat, sheets, timeline bar, HUD, tracker, dialogs. Popped-out windows are their own viewports and never reached the map's unhandled input. In Nico's running app I checked that the hovered control over the free map is null, so zooming there works as before.

Test (`tools/test_token_moves.gd`): a wheel over a ScrollContainer that has nothing to scroll leaves the zoom alone, and over the free map it still zooms. Without the fix the test fails.

Commit 882369c. It also adds explicit types to the TASK-88 set-back code, which the editor couldn't infer.
<!-- SECTION:FINAL_SUMMARY:END -->
