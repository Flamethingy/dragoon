---
id: TASK-2
title: Sketch event format and first calendar
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-01 11:17'
updated_date: '2026-11-01 13:05'
labels:
  - decision
  - events
dependencies: []
documentation:
  - Dragoon Concept
  - doc-1
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design the event record (type, entity, in-world day + time of day, real date, session, payload) and a first calendar definition that only formats the day number (concept: Timeline and calendars, Next steps 3). Decide the storage (JSONL vs SQLite, one log per campaign?) and which changes become events.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Event format documented with field list and 3+ example events (move, item gained, HP change)
- [x] #2 Storage decision (JSONL or SQLite) recorded with reasoning
- [x] #3 First calendar definition file formats a day number into a readable date
- [x] #4 List of MVP event types agreed
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Write backlog/docs/event-format.md (fields, examples, storage choice, MVP event types). Add calendars/default.json and scripts/timeline/calendar.gd to format a day number. Add a headless test.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Proposal in doc-1 "Event format": the record fields (id, type, entity, day, time, real, session, by, data, optional undoes), 4 examples, JSONL per campaign (`<campaign>/events.jsonl`) with reasoning, and 13 MVP event types. Calendar: `calendars/default.json` (placeholder "Dragoon Reckoning", 335 days, festivals, eras) and `WorldCalendar` in `scripts/timeline/calendar.gd`. `tools/test_calendar.gd` passes headless. AC4 ("agreed") is waiting for Nico or the group to confirm the type list.

2026-11-01: Nico approved the 13 MVP event types as a starting set ("we definitely need to extend later"). `entity.sent` source now names the package: `core:<package>/<kind>/<id>`. Follow-up for more event types: TASK-17.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Event format in doc-1 (record fields, examples, JSONL per campaign, 13 MVP types approved by Nico as the starting set; more in TASK-17). Calendar: calendars/default.json + WorldCalendar, test tools/test_calendar.gd. Implemented in EventLog/Replay (TASK-9).
<!-- SECTION:FINAL_SUMMARY:END -->
