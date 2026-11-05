---
id: TASK-86
title: 'Timeline: purge recent events / set the timeline back to a point'
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-02 13:32'
updated_date: '2026-11-02 14:37'
labels:
  - timeline
  - feature
dependencies:
  - TASK-83
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-02: the DM can set the timeline back to a chosen moment and purge everything after it (e.g. "that whole fight didn't happen").

Append-only: a single `timeline.rewound` event (to event id X) makes every later event ineffective, the world clock goes back to that moment, and it can itself be undone ("un-purge"). A confirmation dialog shows how much would be dropped. Maybe also offer "fork from here" (forked timelines already exist) as the non-destructive alternative.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 DM can pick a moment and rewind the timeline to it after confirming
- [x] #2 Everything after it stops counting (state, bar, encounters); the clock goes back
- [x] #3 The rewind can be undone
- [x] #4 Players can't do it; all clients update
- [x] #5 Headless test
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 0a9dfd2 (shared with TASK-85).

**Decision (Nico):** set-backs stay append-only and restorable; nothing is deleted.

**Setting back**
- "Set back to here" shows on the DM's bar while looking back.
- A confirmation dialog names the moment.
- NetTable.rewind_to(upto) appends one `timeline.rewound` event `{to, ids}` that cuts every effective event after the moment. Session markers and earlier set-backs stay.

**What a set-back changes**
- EventLog.is_undone counts cut events as undone, so state, bar and encounters follow.
- The clock goes back to the moment (recomputed; inserted and cut events don't count).
- Both tables refresh.

**The faded branch**
- TimelineSync sends the DM a "branches" list (the cut moments); players don't get it.
- The bar draws it faded above the line, with a hover note.
- Right-click it, then confirm, to restore: undoing the set-back brings the events and the clock back.

**Reloading** the log keeps all of it.

**Test:** tools/test_past_edits.gd. Full suite: 62/62.
<!-- SECTION:FINAL_SUMMARY:END -->
