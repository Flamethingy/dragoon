---
id: TASK-88
title: >-
  Timeline: setting the time back deletes everything after it (no
  split/branches)
status: Done
assignee: []
created_date: '2026-11-04 12:56'
updated_date: '2026-11-04 13:13'
labels:
  - timeline
  - simplify
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-04: the split-timeline function is too complicated. When the DM turns the time back, **everything that happened after that point is simply deleted**.

**Today** (TASK-86, `timeline_bar.gd` `_ask_split` / `rewind_requested`, `timeline_line.gd` branches, `EventLog._rewound`):
- dragging the orange current-time triangle into the past asks "Split the timeline here?";
- a `timeline.rewound` event cuts the later events off;
- they stay as a faded branch above the line that can be brought back (`restore_requested`).

**New**
- Dragging the orange triangle into the past asks once, e.g. "Set the time back to <moment>? The N events after it are deleted for everyone."
- On confirm, the events after that moment are **really removed** from the timeline's event log, and the world clock goes back. All clients update.
- No faded branches, no "bring back" and no restore menu. Remove that UI and code, including the `_rewound` bookkeeping, if nothing else needs it.
- Undo or correct a single event (TASK-85 a/b) stays as it is.
- Acting on the table while scrubbed back (TASK-85 c, events inserted in the past): check whether it's still needed. If it's the same "split" complexity, replace it with "set the time back here first?" (deleting what came after). Ask Nico if unsure.
- Check how this works with forks: a forked timeline inherits its parent's events up to the fork. Deleting in the parent must not break a fork, or else warn.

The event log was append-only on purpose (doc-1 Event-format). This is Nico's explicit decision to allow real deletion when rewinding, so update doc-1 / package-format accordingly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Dragging the current time into the past asks once and then deletes all later events (file and memory), the clock goes back, all clients update
- [x] #2 No branches / restore UI left on the timeline line
- [x] #3 Single-event undo and edit still work
- [x] #4 Forks stay consistent (or the DM is warned)
- [x] #5 doc-1 / docs mention that rewinding deletes
- [x] #6 Timeline tests updated and passing
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Setting the time back now really deletes. Commit 65ddd5c.

- **Asking:** dragging the orange current-time triangle into the past asks once: "Set the time back to <moment>? The N events after it are deleted for everyone. … This can't be undone." The dialog also names the forks that will get their own copy of the history (`NetTable.set_back_preview`).
- **Deleting:** on yes, `NetTable.set_back` → `EventLog.set_back` removes every event after that moment (in timeline order) from `events.jsonl` (a temp file is swapped in) and from memory. Kept are:
  - the events up to the moment;
  - undo markers of kept events;
  - session marks, moved back to that moment.
- **Afterwards:** the clock goes back (plus the minutes past the moment where the DM let go). A `rewritten` signal rebuilds the timeline bar, tokens, combat and roll/chat log on every client.
- **Removed:** the faded branches, the restore menu and signal, `timeline.rewound`/`_rewound` bookkeeping and `TimelineSync._branches`.
- **Old logs:** a log that still has `timeline.rewound` events is migrated once when opened. Cut-off events are deleted and the old file is kept as `events.jsonl.bak-rewound`.
- **Forks:** a fork that inherited a deleted event, or whose fork point is past the last kept event (ids would be reused), is made independent first by `Timeline.detach`: the inherited events are copied into its file, `parent` is cleared and `forked_from` remembers where it came from. A fork can't be set back before its fork point; the DM gets an error message.
- **Unchanged:** single-event undo and correction (TASK-85 a/b) work as before (tested). Acting on the table while looking back (TASK-85 c, `after` inserts) is untouched: it's an insert, not a split, so I kept it. This is a question for Nico, see below.
- **Docs:** doc-1 (id, undoes, Storage section) and timelines.md updated.
- **Tests:** `test_past_edits` rewritten for deletion, forks, the error before a fork point and migration. `test_timeline_bar` and the other timeline/event tests pass. Full suite: only the known `test_concentration` failure (`test_import_ui` failed once, then passed twice; flaky).

Open for Nico: should acting on the table while looking back (TASK-85 c) stay, or become "Set the time back here first?"
<!-- SECTION:FINAL_SUMMARY:END -->
