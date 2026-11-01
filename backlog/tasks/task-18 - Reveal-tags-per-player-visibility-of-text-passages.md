---
id: TASK-18
title: 'Reveal tags: per-player visibility of text passages'
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-01 12:58'
updated_date: '2026-11-01 13:20'
labels:
  - mvp
  - network
  - events
dependencies: []
documentation:
  - reveal-visibility
  - doc-1
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement the data side of [[reveal-visibility]]: parse `<reveal id for>` tags (nested, inline and block) and `%% %%` (DM-only) in any Markdown text; compute who sees what from the tag plus `reveal.changed` events up to the current moment; filter per recipient on the DM host before sending. Replaces the marker filter in `scripts/net/secrets.gd` (Mochi's first proposal is dropped: no `dm_` keys, `[!dm]` callouts or DM headings).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Parser handles inline, block and nested reveal tags plus %% comments; tested headless
- [x] #2 Visibility at a moment = tag 'for' + reveal.changed events up to that moment; rewinding hides revealed text again
- [x] #3 The host strips hidden passages per recipient before sending; a player client never receives text it may not see (test with the amulet example)
- [x] #4 reveal.changed is added to the event doc and the event log
- [x] #5 Old secret markers removed from secrets.gd and the examples
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Reveal (scripts/text/reveal.gd) parses <reveal id for> tags (inline, block, nested = intersection; unclosed = hidden; no `for` = DM) and %% %% (DM-only). Visibility = tag `for` + reveal.changed events up to the moment (EventLog.change_reveal, Reveal.grants_from); rewinding hides again. The host filters entries (Campaign.entry_view, RPC request_entry/receive_entry) and session notes for each recipient. Visible tags keep the current `for` so TASK-19 can draw frames. NetTable.change_reveal logs the event and pushes the new view live. reveal.changed is in doc-1. secrets.gd is removed. Tests: tools/test_reveal.gd and tools/test_net_table.gd (amulet r7/r8). Commit bfdb697. Open question: players can request any entry by ref. They only see untagged text, but whether the existence of an entry is itself secret is a question for TASK-6/21.
<!-- SECTION:FINAL_SUMMARY:END -->
