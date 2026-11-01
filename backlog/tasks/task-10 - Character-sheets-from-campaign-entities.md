---
id: TASK-10
title: Character sheets from campaign entities
status: Done
assignee: []
created_date: '2026-11-01 11:17'
updated_date: '2026-11-01 14:03'
labels:
  - mvp
  - sheets
dependencies:
  - TASK-6
  - TASK-9
documentation:
  - Dragoon Concept
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MVP: show character sheets built from campaign entity frontmatter in our fixed sheet layout (no settings). Changes such as HP go through the event log instead of overwriting the file.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Clicking a token opens its sheet (stats, HP, AC) and info page
- [x] #2 Players see their own PC sheet; DM sees all
- [x] #3 HP and other edits are recorded as events, not written into the .md file
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Clicking a token opens a SheetPanel: a fixed layout built on the host from the campaign copy plus its events (Replay, with reveals applied). The DM sees every sheet; a player sees their own PC's full sheet and only the info page for any other creature. Damage/Heal (temp HP absorbs damage first), Temp HP and AC become hp.changed / sheet.changed events, checked by the host; pcs.json is never written. Open sheets and token hovers update live. Test: tools/test_sheets.gd. Commit: 6577260.
<!-- SECTION:FINAL_SUMMARY:END -->
