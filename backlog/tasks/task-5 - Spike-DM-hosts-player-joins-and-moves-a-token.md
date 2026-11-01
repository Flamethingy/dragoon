---
id: TASK-5
title: 'Spike: DM hosts, player joins and moves a token'
status: To Do
assignee: []
created_date: '2026-11-01 11:17'
labels:
  - spike
  - network
dependencies:
  - TASK-2
  - TASK-3
documentation:
  - Dragoon Concept
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Networking spike (concept: Next steps 5, Architecture): the DM client hosts over ENet, one player client joins, sends a move request, the DM validates and broadcasts it, and the move is appended to the event log.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 DM instance hosts, a second instance joins via IP and port
- [ ] #2 Player move is a request; only the DM changes state and broadcasts
- [ ] #3 Both clients see the token move
- [ ] #4 The move is written to the event log in the TASK-2 format
<!-- AC:END -->
