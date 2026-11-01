---
id: TASK-56
title: 'Rules P1: conditions on tokens and sheets'
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
labels:
  - rules
  - phase-1
  - combat
dependencies:
  - TASK-53
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- Apply and remove conditions from the token context menu, the sheet and roll cards (`condition.applied/removed`).
- Icons on tokens, a list on the sheet with the rules text as a tooltip (from dragoon-core, edition-aware).
- Exhaustion with levels (2014: table, 2024: −2 per level).
- Condition immunity: warning when applying (not blocked).
- Mechanical flags feed the roll toggles: e.g. poisoned → disadvantage preselected on attacks/checks, restrained → attackers get advantage. Always just preselected, never forced.
- Optional duration fields (used by Phase 2).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Conditions can be applied/removed from token, sheet and roll cards as events
- [ ] #2 Token icons and sheet list with tooltips
- [ ] #3 Exhaustion levels per edition
- [ ] #4 Immunity warning
- [ ] #5 Condition flags preselect adv/dis on rolls
<!-- AC:END -->
