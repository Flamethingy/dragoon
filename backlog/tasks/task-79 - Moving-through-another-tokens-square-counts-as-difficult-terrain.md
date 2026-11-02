---
id: TASK-79
title: Moving through another token's square counts as difficult terrain
status: To Do
assignee: []
created_date: '2026-11-02 01:16'
labels:
  - rules
  - map
  - movement
  - feedback
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico's feedback 2026-11-02: when a move passes through another creature's square, that square costs double distance (5e: another creature's space is difficult terrain). The movement pips/ruler (TASK-62) count it. Later, make it a world setting (on/off, maybe only for hostile creatures), together with the rules settings (TASK-60).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Squares occupied by another token cost double movement
- [ ] #2 The ruler and remaining movement show the doubled cost
- [ ] #3 Warn, never block (fits rules-automation.md)
- [ ] #4 World setting to turn it off (can be a follow-up)
<!-- AC:END -->
