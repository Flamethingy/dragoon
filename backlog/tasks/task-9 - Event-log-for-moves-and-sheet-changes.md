---
id: TASK-9
title: Event log for moves and sheet changes
status: To Do
assignee: []
created_date: '2026-11-01 11:17'
labels:
  - mvp
  - events
dependencies:
  - TASK-2
documentation:
  - Dragoon Concept
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MVP: every token move and sheet change is appended to the campaign's event log from day one, with in-world day, real date and session number. Sheets are computed from events; rewind UI comes later.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Moves and sheet changes are appended as events (append-only)
- [ ] #2 Each event has in-world day/time, real date and session number
- [ ] #3 A sheet's current state can be rebuilt from its events
- [ ] #4 Log survives restart and is loaded on host start
<!-- AC:END -->
