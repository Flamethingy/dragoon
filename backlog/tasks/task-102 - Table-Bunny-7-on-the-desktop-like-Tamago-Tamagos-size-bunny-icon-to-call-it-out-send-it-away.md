---
id: TASK-102
title: >-
  Table Bunny 7: on the desktop like Tamago, Tamago's size, bunny icon to call
  it out / send it away
status: Done
assignee: []
created_date: '2026-11-04 16:56'
updated_date: '2026-11-04 16:56'
labels:
  - ai
  - bunny
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico (2026-11-04):
- The bunny shouldn't be stuck inside the game window. It should walk around the desktop like Tamago does.
- Make it as big as Tamago.
- Put a bunny icon in the lower left corner of the VTT. Clicking it spawns the bunny; clicking it again makes it disappear.

How it works:
- BunnyDesk is Tamago's ScreenWorld: a transparent, borderless, always-on-top native window over the usable area of the screen Dragoon is on. Clicks pass through it except on the bunny and its bubbles.
- The bunny walks along the taskbar, can jump up onto Dragoon's window top and ride along with it.
- Where windows can't be see-through, the bunny falls back to living inside Dragoon's window.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The bunny lives in a see-through always-on-top desktop window and walks along the taskbar; clicks pass through except on the bunny and its bubbles
- [x] #2 It can stand on, jump onto and ride along on Dragoon's window top, and falls when the window is gone
- [x] #3 It follows Dragoon's window to another screen; where see-through windows aren't available it stays inside Dragoon
- [x] #4 It is Tamago's size (210 px); 'small' is an option
- [x] #5 A bunny icon in the lower left corner calls it out (puff) and sends it away (puff); the right-click menu can switch between desktop and inside Dragoon
- [x] #6 Tests pass
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 3549326.

**BunnyDesk** (`scripts/bunny/bunny_desk.gd`, a port of Tamago's ScreenWorld):
- a native (`force_native`), borderless, transparent, always-on-top window over the usable area of the screen Dragoon's window is on;
- it checks every second and follows Dragoon to another screen;
- a click-through polygon around the bunny, its bubble and its badge; the whole window while the bunny is carried, falls or a puff plays;
- `platforms()` gives Dragoon's own window top (windowed mode only, not too close to the screen top).

TableBunny got Tamago's platform logic:
- `_support`, landing on the highest platform it passes;
- `_try_jump` up to 260 px (it hops in place when there's nothing to jump onto);
- it rides along when the window moves, and falls when it walks off or the window is gone.

Other changes:
- **Sizes:** "normal" is 210 px (Tamago's height_px), "small" is 140. The old "big" maps to normal.
- **Icon:** BunnyButton in the lower left corner, with Tamago's icon recoloured in the host's colours. It's dimmed while the bunny is away; a click calls it out or sends it away, in a puff.
- **HUD:** DEFAULT_HUD moved two cells to the right to make room for the icon. Layouts already saved are not changed.
- **Right-click menu:** "Stay inside Dragoon" / "Walk on the desktop" (per client), and "Send it away".
- **Project:** `display/window/per_pixel_transparency/allowed=true`.
- TableUI.home_bunny() moves the bunny between the desk and Dragoon's window.
- If transparency isn't available (headless), it stays inside Dragoon.

Checked in a real run: the app hosts, the bunny stands on the taskbar of Dragoon's screen at Tamago's size, its bubble shows, and the icon sits in the corner.

Tests: test_table_bunny was extended:
- jumping onto a window top, standing on it, riding along, falling when it's gone;
- the click-through polygon;
- the icon toggling with puffs;
- it stays inside Dragoon when headless.
app, bunny_net, close_buttons, character_hud, sheets and detached_pages pass.
<!-- SECTION:FINAL_SUMMARY:END -->
