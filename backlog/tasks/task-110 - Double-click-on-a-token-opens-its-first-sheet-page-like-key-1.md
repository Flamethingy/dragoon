---
id: TASK-110
title: Double-click on a token opens its first sheet page (like key 1)
status: Done
assignee: []
created_date: '2026-11-04 23:48'
updated_date: '2026-11-04 23:48'
labels:
  - hud
  - sheets
  - map
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-04: "When double clicking on a token lets also open the first page (so the same when we press 1)".
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A double-click on a token I control makes it active and opens sheet page 1 (open, not toggle)
- [x] #2 Tokens I don't control open nothing
- [x] #3 Tests pass
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Changes:
- **TokenGrid** has a new signal `token_double_clicked(entity)`. It fires on the second press of a left double-click on a token.
- **`CharacterHud.open_first_page(ref)`** handles it:
  - only for tokens in `controlled()` (the DM: everything; a player: their own), and not while the layout editor is open;
  - it makes the token active and calls `pages.open(0)`;
  - unlike key 1, it doesn't toggle: a second double-click keeps the page open.
- **test_character_hud** covers: a double-click on a token I don't control opens nothing; on my token it opens page 1; the map reports a real double-click event on a token.
- **Other suites:** app, detached_pages, net_table, sheet_lists, token_look and token_moves pass. test_tokens prints "all good", then crashes on quit, as it did before this change.
<!-- SECTION:FINAL_SUMMARY:END -->
