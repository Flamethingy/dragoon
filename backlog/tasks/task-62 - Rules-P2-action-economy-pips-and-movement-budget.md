---
id: TASK-62
title: 'Rules P2: action economy pips and movement budget'
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
labels:
  - rules
  - phase-2
  - combat
dependencies:
  - TASK-58
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- The HUD shows action, bonus action, reaction and object interaction pips for the active creature. Using an action marks a pip, and they reset at the start of its turn. Display only, never blocking.
- Movement: the trail shows metres used vs speed (Rules module, incl. conditions like restrained = 0). Over speed = warning colour. Dash doubles it.
- Difficult terrain comes later (P5).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Action economy pips on the HUD, reset per turn, set by used actions
- [ ] #2 Movement used vs speed shown with warning over budget
- [ ] #3 Never blocks the action
<!-- AC:END -->
