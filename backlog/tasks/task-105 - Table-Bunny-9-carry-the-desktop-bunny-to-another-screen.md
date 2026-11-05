---
id: TASK-105
title: 'Table Bunny 9: carry the desktop bunny to another screen'
status: Done
assignee: []
created_date: '2026-11-04 17:56'
updated_date: '2026-11-04 17:56'
labels:
  - ai
  - bunny
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico (2026-11-04): it's fine that it only walks on the taskbar, but it should be possible to pull it to other screens.

How it works:
- While the bunny is carried with the mouse, BunnyDesk follows the real cursor (Tamago does the same). When the cursor moves over another screen, the desk window moves to that screen with the bunny under the cursor.
- The chosen screen is saved per client (TableBunny setting "screen"). The desk then stops following Dragoon's window until "Back to Dragoon's screen" is picked in the bunny's menu.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Carrying the bunny over another screen moves it there, under the cursor; let go it falls to that screen's taskbar
- [x] #2 It stays on that screen (saved per client) even when Dragoon's window is elsewhere
- [x] #3 Its menu has 'Back to Dragoon's screen'
- [x] #4 Tests pass
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit fbdcf51.

**BunnyDesk:**
- `carry(mouse)`: while the bunny is carried with the real mouse, the desk follows the OS cursor every frame. When the cursor is over another screen, the desk moves there with `set_screen(over, carrying = true)`, so the bunny isn't dropped; it stays under the cursor, and the screen is saved as `TableBunny.setting("screen")`.
- `follow_main_window()` uses the saved screen when there is one, and never switches while the bunny is carried.
- `back_to_dragoon()` clears the saved screen.

**TableBunny:**
- `carried_by_mouse()`.
- The let-go safety net uses `DisplayServer.mouse_get_button_state()`, like Tamago, so the release also counts after the window moved.
- Its menu has "Back to Dragoon's screen" while it lives on another screen.

**Checked in a real run with 3 screens:**
- carried from screen 1 to screen 0: the desk moved there and the bunny stayed under the cursor;
- let go: it fell onto that screen's taskbar;
- it stayed there when the desk checked Dragoon's screen;
- "back" returned it to screen 1.

Tests: table_bunny, bunny_net and app pass. Headless has a single screen, so the screen change itself was only checked in the real run.
<!-- SECTION:FINAL_SUMMARY:END -->
