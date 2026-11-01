---
id: TASK-12
title: Dice roller that knows the stats
status: Done
assignee: []
created_date: '2026-11-01 11:18'
updated_date: '2026-11-01 14:07'
labels:
  - mvp
  - dice
dependencies:
  - TASK-10
documentation:
  - Dragoon Concept
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MVP: roll by name ("roll Perception", "Dex save", "attack with Longsword") using the character's stats instead of typing formulas. Results are shown to everyone (with an optional DM-only roll).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Skill checks, saves and attacks roll from sheet stats with the right modifier
- [x] #2 Manual formulas (2d6+3) still work
- [x] #3 Rolls appear in a shared roll log; DM can roll hidden
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Dice (scripts/dice/dice.gd) handles formulas (NdM, kh/kl, +/-) and roll-by-name from sheet stats: skills, saves, ability checks, initiative, attacks from feature `attack` data, advantage/disadvantage. The host rolls and logs dice.rolled, and everyone sees it in a roll log under the notes. Players roll only for their own PC; the DM can roll hidden. Sheet entries are clickable roll links. Late joiners and restarted hosts get the session's rolls. Test: tools/test_dice.gd. Commit: 12150d3.
<!-- SECTION:FINAL_SUMMARY:END -->
