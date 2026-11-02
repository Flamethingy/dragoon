---
id: TASK-62
title: 'Rules P2: action economy pips and movement budget'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
updated_date: '2026-11-02 02:03'
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
- [x] #1 Action economy pips on the HUD, reset per turn, set by used actions
- [x] #2 Movement used vs speed shown with warning over budget
- [x] #3 Never blocks the action
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices (Mochi): events action.used / action.unused {kind: action|bonus|reaction|object, what}; the turn window starts at the creature's (or its group's) last combat.turn (which now records its entity), else combat.started. Moves count Chebyshev squares × 1.5 m. Attacks/save actions mark the pip by where the feature is listed (bonus_actions/reactions, else action; Multiattack = one action). Dash = an action that doubles speed. Rules.speed: walk speed, 0 for grappled/restrained etc., halved by speed_half, 2024 exhaustion −1.5 m/level. The HUD "turn" piece is in the catalog but not in the default layout (no churn). Never blocks: over budget the trail and label turn orange/red.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Action economy (commit b1d7f90): NetTable.turn_usage(ref) / mark_action; attacks and save actions use their pip; tracker rows carry `usage`; MovePlans shows "used+planned / speed m" in orange when over; new HUD widget "turn" (A/B/R/O pips, Move x / y m, Dash). Test tools/test_turn_economy.gd; full suite 42/42 green.
<!-- SECTION:FINAL_SUMMARY:END -->
