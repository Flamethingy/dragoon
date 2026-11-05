---
id: TASK-113
title: >-
  Windows are always their own windows (no pulling out of the game view); only
  the chat stays dockable
status: Done
assignee: []
created_date: '2026-11-05 00:14'
updated_date: '2026-11-05 01:30'
labels:
  - ui
  - panels
  - windows
  - concept
dependencies: []
priority: medium
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-05: switch from "drag a window out of the game view to detach it" to **"windows are always detached and their own thing"**. Integrating them into the main screen has no benefit except docking, and most screens can't really be docked anyway.

- **Always their own OS windows:** Compendium / Book, character sheets and sheet pages, Rules, Timeline / Calendar, Packages, editors... They open as borderless windows with the TASK-91 bar (close / minimise / maximise; maximise like the fix in 5079d12).
- **Exception: the chat** stays dockable inside the main screen (and can still be detached).
- **Remembered** per window: position, size, screen; it reopens there.
- **Simplify:** remove dock zones, pull-out and dock-back logic and the in-app floating mode for everything except the chat. Check what DockPanel still needs.
- Watch out for:
  - focus and always-on-top behaviour with the main window (minimising Dragoon minimises its windows; Alt-Tab);
  - several screens;
  - TASK-90 (the mouse wheel stays per window);
  - drag & drop from a window onto the map (TASK-93 / 94) has to keep working across windows;
  - in the editor's embedded Game view (see d26b058), windows can't be embedded, so check that it still works there (force_native).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
"Timeline / Calendar" in the list: I read it as the app's Timeline view (a Dock panel, now its own window). The timeline bar strip is left dockable; Nico to decide.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 6463217.

- **DockPanel `always_window`:**
  - Shown, the panel opens straight in its own borderless OS window with the TASK-91 bar (minimise / maximise / close).
  - The window is `transient`, owned by Dragoon's window, so it minimises with it and is grouped in Alt-Tab.
  - It reopens where it was last (position and size, so also the screen). If that spot is on no screen any more (a monitor unplugged), it comes back centred on the program's screen.
  - Dragged over the program it stays a window; `dock_back` closes it instead; closing hides it and saves its place.
- **Dock `windows_only`:** every app panel (Compendium / Book, world, notes, rules, sheet, timeline view, logs...) goes through such a DockPanel.
- **Unchanged:**
  - The chat (ChatBox) still docks, floats and pops out as before.
  - Detached sheet pages (TASK-92) were already their own windows.
  - EntryWindow is its own window.
  - Drag & drop from a window onto the map still goes through `App.drop_outside`, which knows popped-out frames.
- **Headless:** headless runs have no own windows (`DockPanel.native_windows` false), so they keep the old in-app places and the existing tests (dock, app, detached pages, timeline bar, character hud) stay green.
- **Real-run check:** tools/check_own_windows.gd, all good:
  - own window, borderless, transient;
  - place 'window';
  - closes and hides;
  - reopens at the same rect;
  - dropped over the program it stays a window;
  - dock_back closes it;
  - a lost place lands on a screen;
  - the chat still docks.
- **Not done:**
  - The Dock's tab-area / dock-zone code isn't deleted yet: headless runs and the chat still use it. It can go once the tests run with native windows.
  - The timeline bar (slim strip at the top) still docks like the chat. Question for Nico: should it become a window too, or wait for TASK-112 (calendar)?
  - The editor's embedded Game view isn't checked by hand (force_native is set as before).
<!-- SECTION:FINAL_SUMMARY:END -->
