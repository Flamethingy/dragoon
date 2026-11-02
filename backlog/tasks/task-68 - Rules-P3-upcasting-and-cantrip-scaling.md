---
id: TASK-68
title: 'Rules P3: upcasting and cantrip scaling'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:45'
updated_date: '2026-11-02 02:54'
labels:
  - rules
  - phase-3
dependencies:
  - TASK-49
  - TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- Casting at a higher slot adds the effect's `scaling.per_slot` dice (or extra targets/duration where structured).
- Cantrips scale with the caster's character level at 5/11/17 (dragoon-core table).
- The roll card shows what was added ("+2d6, slot 5").
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Upcast adds per-slot dice
- [x] #2 Cantrips scale with character level
- [x] #3 Roll card shows the scaling
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices: if the per-slot die matches the base die the count grows (8d6 → 10d6), otherwise it's appended (3d4+1d6). Cantrips multiply the first die's count by the dragoon-core 5/11/17 table. Extra targets per slot are only noted on the card; picking them stays with the player (bookkeeping, not decisions). Scaling comes from the effects first, then from the "At Higher Levels" text.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Rules.scaled(damage, scaling, base, cast_level, caster) → {damage, note, targets} and Rules.scaling_of(entry). They're used for spell attacks (_handle_attack spells branch), save spells (_handle_save_action) and healing/other spells (_handle_use; a structured heal "1d8+mod" uses the casting modifier). Attack and save cards show the note ("+2d6, slot 5" / "2d10, level 5"). Test: tools/test_scaling.gd. Fixed a sync race in test_character_hud. Commit 6f58dc2.
<!-- SECTION:FINAL_SUMMARY:END -->
