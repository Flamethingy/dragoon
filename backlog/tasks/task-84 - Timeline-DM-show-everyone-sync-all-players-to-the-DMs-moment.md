---
id: TASK-84
title: 'Timeline: DM "show everyone" (sync all players to the DM''s moment)'
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-02 13:31'
updated_date: '2026-11-02 14:13'
labels:
  - timeline
  - net
  - feature
dependencies:
  - TASK-83
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-02: the DM can pull every player's timeline to the moment the DM is looking at, e.g. for a flashback or to show what happened.

- A "Show everyone" toggle on the bar (DM only): while it's on, every client's cursor follows the DM's, and players see a hint ("The DM is showing ...").
- Players can't scrub away while it's on; switching it off gives them back their own cursor (back at now).
- Players stay locked from acting while they're shown the past, as with TASK-83.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 DM can switch "show everyone" on and off
- [x] #2 While on, all players' cursors follow the DM's live and their tables show that moment
- [x] #3 Players get a hint and can't scrub away; off returns them to now
- [x] #4 Headless multi-peer test
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 5b892d7.
- **The toggle:** a "Show everyone" button on the DM's TimelineBar calls NetTable.show_everyone(on). While on, every change of the DM's cursor (look_back(upto, at)) pushes `dm_showing(on, at, upto)` and a past view (past_shown) to every peer. A player who joins while it's on is pulled in by the hello handler.
- **Player side:** the cursor follows the DM's, the line's cursor is locked (no scrubbing), and the Now button hides. The head reads "The DM is showing: …". look_back is ignored while shown, and the host refuses moves through `_backs`.
- **Off:** everyone returns to now with their own cursor; the DM can keep looking back alone.
- **Test:** tools/test_show_everyone.gd (DM, Bob and a late Ann) passes. Full suite: 60/61. test_death failed once in the suite run but passed 3/3 alone; a timing flake in its initiative check that has nothing to do with this change.
<!-- SECTION:FINAL_SUMMARY:END -->
