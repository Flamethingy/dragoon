---
id: TASK-76
title: Token facing triangle follows the trail direction in real time
status: To Do
assignee: []
created_date: '2026-11-02 01:16'
labels:
  - map
  - tokens
  - feedback
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico's feedback 2026-11-02: when a token moves along its trail, its direction triangle should turn live to point along the current path segment, not only at the end.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The triangle rotates to each segment's direction while the token moves along the trail
- [ ] #2 Final facing stays the last segment's direction (or as set)
- [ ] #3 Same on all clients
<!-- AC:END -->
