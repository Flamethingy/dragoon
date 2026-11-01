---
id: TASK-2
title: Sketch event format and first calendar
status: To Do
assignee: []
created_date: '2026-11-01 11:17'
labels:
  - decision
  - events
dependencies: []
documentation:
  - Dragoon Concept
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design the event record (type, entity, in-world day + time of day, real date, session, payload) and a first calendar definition that only formats the day number (concept: Timeline and calendars, Next steps 3). Decide the storage (JSONL vs SQLite, one log per campaign?) and which changes become events.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Event format documented with field list and 3+ example events (move, item gained, HP change)
- [ ] #2 Storage decision (JSONL or SQLite) recorded with reasoning
- [ ] #3 First calendar definition file formats a day number into a readable date
- [ ] #4 List of MVP event types agreed
<!-- AC:END -->
