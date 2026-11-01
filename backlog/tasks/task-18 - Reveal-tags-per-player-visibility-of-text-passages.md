---
id: TASK-18
title: 'Reveal tags: per-player visibility of text passages'
status: To Do
assignee: []
created_date: '2026-11-01 12:58'
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
- [ ] #1 Parser handles inline, block and nested reveal tags plus %% comments; tested headless
- [ ] #2 Visibility at a moment = tag 'for' + reveal.changed events up to that moment; rewinding hides revealed text again
- [ ] #3 The host strips hidden passages per recipient before sending; a player client never receives text it may not see (test with the amulet example)
- [ ] #4 reveal.changed is added to the event doc and the event log
- [ ] #5 Old secret markers removed from secrets.gd and the examples
<!-- AC:END -->
