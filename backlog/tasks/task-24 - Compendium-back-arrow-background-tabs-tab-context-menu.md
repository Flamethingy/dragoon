---
id: TASK-24
title: 'Compendium: back arrow, background tabs, tab context menu'
status: To Do
assignee: []
created_date: '2026-11-01 13:40'
updated_date: '2026-11-01 13:49'
labels:
  - ui
dependencies:
  - TASK-22
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up to TASK-22 (tabs), from Nico's testing:

1. **Back button:** a left arrow right next to the title of the current page (full-view tab header) that **closes the current tab and jumps back to the previously active tab**. The compendium keeps a tab history (opening or switching to a tab pushes the old one; closed tabs are skipped). Also on Alt+Left and the mouse "back" side button (MOUSE_BUTTON_XBUTTON1). Closing on Back is a setting (default on) because Nico wants to try how it feels; when it's off, Back only switches.
2. **Middle-click = background tab:** middle-clicking a card (or a wikilink/feature link) opens the entry in a new tab **without switching to it**, like browser tabs. The new tab appears right after the current one (consecutive background opens line up in order) and gets a short highlight. Left-click/double-click behaviour from TASK-22 stays as it is.
3. **Tab context menu:** right-clicking a tab offers Close, Close all tabs, Close tabs to the left, Close tabs to the right. The Browse tab is never closed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Middle-click on a card, wikilink or feature opens a new tab in the background; the current tab stays focused
- [ ] #2 Background tabs are inserted right after the current tab in opening order and briefly highlighted
- [ ] #3 An entry that is already open is not duplicated by middle-click (its tab just gets highlighted)
- [ ] #4 The back arrow next to the page title closes the current tab and switches to the previously active one (disabled on Browse / without history; closed tabs are skipped)
- [ ] #5 Alt+Left and the mouse back button do the same
- [ ] #6 Back-closes-tab is a setting (default on) so Nico can try both behaviours; when off, Back only switches tabs
- [ ] #7 Right-clicking a tab opens a context menu: Close, Close all tabs, Close tabs to the left, Close tabs to the right (Browse is never closed; entries that don't apply are disabled)
- [ ] #8 The quick preview on the right of the Browse tab drops the 'Full text' fold: it always shows everything (key facts, stat block, full Markdown text) and simply scrolls
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-01 (Nico): Back should also close the tab it leaves ("I'll test and see how it feels"), so it's a setting with default on. Forward navigation dropped, since it doesn't fit closing. Added a tab context menu with Close all / to the left / to the right.

2026-11-01 (Nico): the right-hand preview doesn't need "Full text". Always show everything; people scroll if they want (AC8).
<!-- SECTION:NOTES:END -->
