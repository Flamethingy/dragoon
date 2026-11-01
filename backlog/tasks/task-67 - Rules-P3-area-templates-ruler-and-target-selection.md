---
id: TASK-67
title: 'Rules P3: area templates, ruler and target selection'
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:45'
labels:
  - rules
  - phase-3
  - map
dependencies:
  - TASK-54
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- Templates on the grid: sphere/circle, cone, line, cube, cylinder, sized in metres. They are placed from an effect's `area` or freely from a toolbar, can be rotated, and are visible to all.
- Tokens inside are selected as targets (5e grid rule: a square counts if the area covers half or more, or its centre). The DM or caster can add or remove targets before rolling.
- Ruler tool: drag to measure in metres (diagonals as in the movement rule).
- Range warning when a target is beyond the spell/weapon range.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All five template shapes placeable, rotatable, visible to all
- [ ] #2 Tokens in the area become targets, editable before rolling
- [ ] #3 Ruler in metres
- [ ] #4 Out-of-range warning
<!-- AC:END -->
