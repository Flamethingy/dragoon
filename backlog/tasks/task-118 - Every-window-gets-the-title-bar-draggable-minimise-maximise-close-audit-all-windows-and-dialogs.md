---
id: TASK-118
title: >-
  Every window gets the title bar: draggable, minimise / maximise / close (audit
  all windows and dialogs)
status: To Do
assignee: []
created_date: '2026-11-05 02:41'
updated_date: '2026-11-05 03:03'
labels:
  - ui
  - windows
  - panels
dependencies: []
priority: high
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-05: many windows still **can't be dragged** and have **no minimise / close buttons**.

**Audit:** go through **every** window, popup and dialog in Dragoon, for example:
- start screen dialogs (new world / timeline, add server, edit world);
- Compendium / Book, entry editor, the item / spell view (TASK-108);
- character sheets and sheet pages, the layout editor (F2);
- Rules, Packages, Import, Notes, Encounters, Calendar / Timeline, Dice;
- bunny chat and bunny settings, confirm dialogs, file pickers.

Write the list into the ticket notes, with each window's state (has the bar / missing).

**Goal:** all of them use the same **TASK-91 bar**:
- dragging by the title moves the window;
- the edges resize it (where it makes sense);
- **minimise / maximise / close** at the top right (maximise uses the screen's usable rect, as in commit 5079d12);
- small confirm dialogs only need dragging plus close (no min/max).

Ideally build one shared base (e.g. a `DragoonWindow` scene / class with the bar) and switch everything to it. That is also the groundwork for **TASK-113** (all windows always on their own), so build it to fit that.

Look and behaviour like the existing popped-out panels: Esc closes where it did before; position and size are remembered.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Notes list every window/dialog with its before/after state
- [ ] #2 Every window can be dragged by its title and has close (and min/max where it makes sense)
- [ ] #3 One shared window base instead of per-window code
- [ ] #4 Position/size remembered; Esc still closes where it did
- [ ] #5 Headless test: each window type has the bar and its buttons work
<!-- AC:END -->
