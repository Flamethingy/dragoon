---
id: TASK-92
title: >-
  Sheet pages (1-9) detachable: pull them out as windows, pinned to their
  character
status: Done
assignee: []
created_date: '2026-11-04 13:14'
updated_date: '2026-11-04 13:34'
labels:
  - ui
  - docking
  - sheets
dependencies:
  - TASK-91
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-04: the sheet pages (keys 1–9, `scripts/hud/sheet_pages.gd`) should be **detachable**, like the other panels: drag a page out of the program window and it becomes its own window (popped out, using the same mechanism as DockPanel / TASK-91: borderless with close, minimise and maximise).

**Pinned to the character:** a detached page shows **the character it was opened for**, not "the active / selected token". It stays open and keeps updating live (HP, slots, ...) when another token gets selected or nothing is selected. Several detached pages are allowed, e.g. page 2 of Borin and page 1 of Aria side by side, or two pages of the same character.
- The window title / label shows the character and page, e.g. "Borin – Spells".
- Keys 1–9 keep working as today for the active character's in-program page; detached windows aren't affected by them.
- Dragging a detached page back over the program docks it back in (it becomes the normal page view again, or just closes, whichever is simpler).
- Detached pages (character, page, window position and size) are remembered per player and reopen with the session.
- Players only get pages of characters they may see (same rules as `sheet_for`).

**Resizing:** for now the window size is just the page at its current design size (or a simple even scale). Nico is still thinking about how pages should resize; don't build reflow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A sheet page can be dragged out of the program into its own window
- [x] #2 A detached page stays bound to its character and keeps updating, also when another token is selected or none
- [x] #3 Several detached pages (different characters / pages) can be open at once
- [x] #4 Dragging it back over the program docks or closes it; close button works
- [x] #5 Detached pages are remembered and reopened per player
- [x] #6 Players can't detach pages of characters they may not see
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit a09b682.

- **Pull out:** drag the page's head (the tab row with the name; the tabs themselves stay buttons) past the edge of the program. `SheetPages.detach(ref, page, screen)` then creates a `DetachedPage` in its own window that goes on following the mouse. The in-program page closes.
- **DetachedPage** (`scripts/hud/detached_page.gd`): a `DockPanel` with the TASK-91 window.
  - Borderless; the edges resize it; minimise, maximise and close buttons; moved by its title.
  - Titled "Borin Stoneshield – Spells & gear" (window and head).
  - Never docks: closing it or dragging it back over the program closes it. If that character is the active one, its page opens in the program.
  - The page is laid out on its grid at the window's size, an even scale with no reflow (the design size to start with).
- **Pinned:** each page has a `PinnedHud` (`scripts/hud/pinned_hud.gd`), a CharacterHud that never shows, never follows the selection and takes no keys. Its `active` stays fixed, so the page's pieces (casting, slots, checks, …) act for that character.
  - `NetTable.keep_sheet(ref, on)` keeps the sheet open while a page shows it; `close_sheet` leaves kept ones alone.
  - It rebuilds on `sheet_received` for its character (and on `table_changed` if it has the turn piece).
  - Keys 1–9 only touch the in-program page.
  - Several at once, including two pages of the same character.
- **Remembered:** character, page and window rect go to `pages.cfg` beside the player's cache, under section "detached", one key per player ("dm" / player id). They are saved on every change and window resize, and reopen once the table is there (`restore_detached`).
- **Rights:** the DM may pull out any creature's pages, a player only those of characters they control (`may_detach`). The host also only sends sheets the player may see. Reopening skips the ones no longer allowed.
- **Also:**
  - Drops of items, spells and features on a detached page go to its character (TASK-94).
  - `EntryDrag.accept_on` holds its root weakly and disconnects when the root is freed. A closed page used to leave a lambda with a freed capture.
- **Test:** `tools/test_detached_pages.gd`.
  - Window, buttons, title.
  - Live update after HP damage while another character or none is active; keys 1–9 don't touch it.
  - Three open at once; saved rect.
  - Drop over the program closes it and opens the page in the program; the close button closes it and the sheet is let go.
  - Reopened in a new HUD.
  - Bob: allowed for Borin but not for Aria, gets the sheet from the host, saved per player.
  - The head-drag gesture pulls the page out and it follows the mouse.
  - entry_drops, entry_preview, character_hud, minimal, app, sheets and forms pass.

Open for Nico: how pages should resize. For now it's an even scale with the window.
<!-- SECTION:FINAL_SUMMARY:END -->
