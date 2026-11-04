---
id: TASK-102
title: >-
  Table Bunny 7: on the desktop like Tamago, Tamago's size, bunny icon to call
  it out / send it away
status: In Progress
assignee: []
created_date: '2026-11-04 16:56'
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
- [ ] #1 The bunny lives in a see-through always-on-top desktop window and walks along the taskbar; clicks pass through except on the bunny and its bubbles
- [ ] #2 It can stand on, jump onto and ride along on Dragoon's window top, and falls when the window is gone
- [ ] #3 It follows Dragoon's window to another screen; where see-through windows aren't available it stays inside Dragoon
- [ ] #4 It is Tamago's size (210 px); 'small' is an option
- [ ] #5 A bunny icon in the lower left corner calls it out (puff) and sends it away (puff); the right-click menu can switch between desktop and inside Dragoon
- [ ] #6 Tests pass
<!-- AC:END -->
