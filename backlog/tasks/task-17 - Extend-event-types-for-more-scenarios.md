---
id: TASK-17
title: Extend event types for more scenarios
status: To Do
assignee: []
created_date: '2026-11-01 12:50'
labels:
  - events
dependencies: []
documentation:
  - doc-1
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The 13 MVP event types (doc-1 Event format) are only a starting set. Nico wants events for all kinds of scenarios. Collect what is missing as features land and add the types with their payloads to the event doc. Candidates already known: conditions (applied/removed), initiative / combat start-end, party split/merge, travel arrivals (`party.arrived`), assistant drafts, spell slots / resources used, rests, death saves, currency, relationships/faction standing, quest progress, weather.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Event doc lists the new types with entity and data fields
- [ ] #2 Each new type has at least one example event
- [ ] #3 Replaying the log rebuilds state for the new types (tests)
<!-- AC:END -->
