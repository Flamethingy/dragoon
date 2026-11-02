---
id: TASK-80
title: Compendium and Book as dockable windows with auto pop-out at the edge
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 01:16'
updated_date: '2026-11-02 10:05'
labels:
  - ui
  - windows
  - feedback
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico's feedback 2026-11-02: the chat can be moved around inside the VTT and detached into its own OS window. Do the same for the Compendium and the Book. On top of that, dragging any dockable window past the edge of the program window turns it into a pop-out window automatically, and dragging a pop-out back over the program window docks it again. Reuse the chat's dock/detach code (TASK-50).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The Compendium and Book can be moved inside the VTT and detached like the chat
- [x] #2 Dragging past the program edge pops the window out
- [x] #3 Dragging a pop-out back over the program docks it again
- [x] #4 Position and state are remembered
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices:
- The chat's dock, float and pop-out code (TASK-50) moved into a shared class, DockPanel (scripts/ui/dock_panel.gd). ChatBox extends it, so there is one implementation for everything.
- On the calm table, the Compendium, the Book (and the Rules page, which opens the same way) now open floating over the table in a DockPanel instead of straight in an OS window. Like the chat, they can be dragged by the title to dock left, right or bottom, float anywhere, be resized, or popped out with "Pop out". The full (non-minimal) layout with tab areas is unchanged.
- Auto pop-out: dragging any DockPanel (chat, Compendium, Book) by its title past the program window's edge turns it into its own OS window under the mouse, and it keeps following the mouse until released.
- Re-dock: dragging a pop-out by its own title (the in-panel head) back over the program window docks it again where it is let go (on a dock zone, otherwise floating there). Dragging by the OS title bar moves it without docking. That way a pop-out can still sit over the program on purpose, which matters on one monitor. The drag is followed with the OS mouse position and button state (DisplayServer), so it also works across monitors.
- Closing a book's own window closes the book (as before); closing the chat's window docks it back (as before).
- Remembered per panel on this computer: dock / size / floating rect / popped out / the window's rect. Chat in chat.cfg as before; books in panels.cfg next to the dock layout (sections panel_compendium, panel_world, panel_rules). A book that was popped out comes back in its own window next time.
- Book pop-out windows are at least 900x650.
- Known headless-only quirk: in the test runner (no native windows, everything embedded), freeing a pop-out right after a cross-window drag can crash Godot's embedder. The test does the TASK-80 checks before that drag. Real Windows uses native windows.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 396e9c8. New DockPanel (dock/float/resize/zones, pop_out/dock_back, outside(), pull_out(), start_carry/carry_to/drop_at with _process following DisplayServer's mouse, saved window rect, close_hides/closed). ChatBox now extends DockPanel. Dock: "float" place via float_panel() (a DockPanel per panel, saved in panels.cfg), remove_panel(), place_of returns float/window for frames, _take_out hides frames. App: minimal views open as "float"; drop_outside also finds popped-out frames' windows; _drop_views uses remove_panel. test_minimal covers floating, pop-out, close, pull past the edge, carry, drop beside / over the program, and what is remembered. New tools/screenshot_float.gd (screenshots checked). Tests: 57/57 green.
<!-- SECTION:FINAL_SUMMARY:END -->
