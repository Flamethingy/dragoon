---
id: TASK-56
title: 'Rules P1: conditions on tokens and sheets'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
updated_date: '2026-11-02 01:26'
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
- [x] #1 Conditions can be applied/removed from token, sheet and roll cards as events
- [x] #2 Token icons and sheet list with tooltips
- [x] #3 Exhaustion levels per edition
- [x] #4 Immunity warning
- [x] #5 Condition flags preselect adv/dis on rolls
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design decisions (Mochi):
- Who may change conditions: the DM, and a player for the creatures they control (their PC, shared PCs). A player's change shows as a DM log line (trust, but visible), like TASK-51.
- Immunity: applied anyway with data.immune = true, plus a hidden warning line for the DM ("applied anyway, undo if that was a mistake") — warn, never block.
- Conditions are public on the table: every player sees the marks (they'd see a prone or grappled creature too).
- Advantage is only preselected inside Dice.resolve when the roll has no explicit choice; "normal" / "straight" or Shift/Ctrl override it. The roll label says why ("disadvantage: poisoned").
- Exhaustion: one condition with a level 1-6 (menu +1/-1); 2014 uses the by-level flags, 2024 subtracts 2 per level from d20 tests.
- Roll cards: the creature's name is a link to its condition menu. "Attacked with advantage" (restrained, prone ...) needs a target and comes with TASK-54.
- The token menu is a right click without dragging (right drag still pans).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 73f2574. set_condition / request_condition (condition.applied/removed, exhaustion level, optional duration), immunity warning, log lines. Tokens carry conditions; TokenMarks draws coloured discs with the short name. Condition menu (right click on a token, sheet "+ condition", a roll card's name) with ticks, edition-aware rules text tooltips and exhaustion +1/-1; the sheet lists conditions with tooltips and a × to remove. Dice.resolve preselects adv/dis from conditions (label says why, explicit choice wins) and applies the 2024 exhaustion penalty. New suite tools/test_conditions.gd; 35 suites green.
<!-- SECTION:FINAL_SUMMARY:END -->
