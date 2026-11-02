---
id: TASK-67
title: 'Rules P3: area templates, ruler and target selection'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:45'
updated_date: '2026-11-02 02:48'
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
- [x] #1 All five template shapes placeable, rotatable, visible to all
- [x] #2 Tokens in the area become targets, editable before rolling
- [x] #3 Ruler in metres
- [x] #4 Out-of-range warning
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices (Mochi):
- AreaLayer (scripts/spikes/area_layer.gd, a child of TokenGrid, input first). Geometry is in cell units.
- Shapes:
  - sphere and cylinder: a circle around a grid corner (one click, snapped)
  - cone: 5e width = length (half angle atan ½)
  - line: length × width, default 1.5 m
  - cube: a square starting at the origin's edge
  - Cone, line and cube take a click for the origin, then aim with the mouse and click again. Esc cancels.
- Coverage (5e grid rule): a square counts if its centre is inside or ≥ half of it (4×4 samples). A token is inside if any of its squares is.
- Shared: the host holds `templates` (in the table view for joiners, plus a templates_set rpc). place/remove/rotate go through request_template; only the placer or the DM may remove or turn one. They are drawn in the placer's account colour, with the covered squares tinted and labelled.
- Toolbar: "Ruler" (drag; metres like moving: Chebyshev squares × 1.5) and "Area" (presets: sphere 3/6 m, cone 4.5/9 m, line 9/30 m, cube 3/6 m, cylinder 6 m; "Remove my areas", the DM removes all).
- Targeting: a spell's area (its effects, else the text) travels with the cast. The attack bar shows "Place area"; placing it makes the creatures inside the targets (not the caster), and they can still be clicked on/off before rolling.
- Range: Rules.range_of ("1.5 m", "24.4/97.5 m", a spell's range_m). Distance is edge to edge, like moving.
  - The attack bar shows "(N out of range)".
  - Attack cards note "out of range" or "long range: disadvantage"; save cards note out of range.
  - Only a warning: nothing is blocked and advantage is not changed by itself.
- Rotating an already-placed template is in the API (rotate_template); there is no on-map rotate handle yet (re-place to re-aim).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Area templates, ruler, area targeting and range warnings (commit b8b4797). Test tools/test_areas.gd (with a joined player); screenshot checked; suite 48/48 green.
<!-- SECTION:FINAL_SUMMARY:END -->
