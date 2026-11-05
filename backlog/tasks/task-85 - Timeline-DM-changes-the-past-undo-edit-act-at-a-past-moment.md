---
id: TASK-85
title: 'Timeline: DM changes the past (undo, edit, act at a past moment)'
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
Nico 2026-11-02: only the DM can change events in the past. The log stays append-only (doc-1 Event-format); every change is a new, undoable event that corrects an old one, and players see the result.

From a box (or while scrubbed back) the DM can:
- (a) **undo/delete** an event of that moment;
- (b) **change its values** (damage, item count, target square, ...) as a correction event that replaces the old one;
- (c) **act on the table while scrubbed back**: a move, HP change, item, etc. is inserted at that moment (stamped with that day/minute) rather than at now.

Later events are recomputed by Replay; ones that no longer make sense (e.g. a dead creature's later move) are flagged/skipped instead of breaking the state. All clients update live.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 DM can undo an event of a past moment from the bar
- [x] #2 DM can edit a past event's values (correction event, the original stays in the log)
- [x] #3 While scrubbed back, DM actions are inserted at that moment
- [x] #4 Later state is recomputed; impossible later events are flagged, not crashing
- [x] #5 Players can't do any of this; all clients update
- [x] #6 Headless test
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 0a9dfd2 (shared with TASK-86).

**Decision (Nico, 2026-11-02, "take your suggestions"):** later events stay as they are. A token moved in the past "jumps" at its next recorded move; nothing is flagged. That replaces AC4's flagging; recomputing later state works through Replay.

**Acting in the past**
- How it's stored and ordered:
  - EventLog.insert_at(anchor): new events get `after` (the anchor chain) and the anchor's day/time, and don't move the clock.
  - Replay.before sorts them right after their anchor.
  - insert_filter (set by the host) lets only the DM's own actions go in; players' RPC actions stay at now.
- Every effective/replay consumer picks the order up automatically.
- The DM looking back is no longer locked: dragging a past token (TokenGrid._past_press) becomes NetTable._past_move, which moves it from its past square, with a trail. Token-menu actions also go in.
- After each insert:
  - the DM's view moves on to it;
  - refresh_tokens updates the present;
  - Show everyone pushes the moment to the players;
  - TimelineSync rebuilds.
- Changed moments get an orange dot on the bar.

**Undo / correct**
- A box opens the Timeline list with exactly that moment's events (moments now carry their ids).
- The list has "Undo event" and "Correct values…". The correction form shows each data field; numbers stay ints.
- A correction (EventLog.correct) undoes the original and inserts a copy with the new data and `corrects` at the original's place. The original stays in the log.

**Players** can't do any of this: the host-only list, and the host refuses their moves while they look back.

**Test:** tools/test_past_edits.gd. Full suite: 62/62.

**Not yet:** the HUD and sheets stay locked for the DM in the past (their HP math uses the present).
<!-- SECTION:FINAL_SUMMARY:END -->
