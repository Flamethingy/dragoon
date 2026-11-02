---
id: TASK-57
title: 'Rules P1: 0 HP, death saves and defeated creatures'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
updated_date: '2026-11-02 01:49'
labels:
  - rules
  - phase-1
  - combat
dependencies:
  - TASK-56
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- Character at 0 HP → Unconscious, and a death save button on their turn (`death_save.rolled`).
- Damage at 0 HP = one failed save (two on a crit). Healing removes Unconscious and resets the saves.
- A natural 20 regains 1 HP; 3 failures = dead (marked, DM can undo).
- Massive damage: warning only.
- Creatures at 0 HP: token marked as defeated (greyed/skull). The DM chooses dead or knocked out; defeated creatures are skipped in the turn order.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 0 HP applies Unconscious and enables death saves on the character's turn
- [x] #2 Damage at 0 counts as failures, healing resets
- [x] #3 Nat 20 / 3 failures handled
- [x] #4 Defeated creatures marked and skipped in initiative
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design decisions (Mochi):
- "Character" = an entry under characters/ (PCs and their sidekicks); everything else is a creature.
- Creatures at 0 HP are marked Dead by default (the common case); the DM switches to knocked out by unticking Dead and ticking Unconscious in the condition menu (Dead is now listed there). Both grey the token.
- Massive damage only warns (DM log line); the DM marks Dead if they follow the rule.
- Three failures mark Dead and tell the DM, who can undo the condition event. Three successes = stable: no more death saves, still Unconscious until healed.
- A dead character who gets healed is not revived automatically; the DM gets a hint.
- The death save prompt comes on their turn in combat (chat link); out of combat the sheet's "roll" link works any time at 0 HP.
- Skipped in the order: dead entries, creatures at 0 HP; a group only when all members are down. Characters at 0 HP keep their turn (for the death save).
- Automation "death_saves" Off disables all of it.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit ffc994e. _after_hp hook in _handle_hp (unconscious at 0, death save failures from damage incl. crits, wake on healing, massive damage warning, creatures marked dead), roll_death_save/request_death_save with nat 1/20, 3 failures → dead, prompt on their turn, sheet roll link, Dead in the condition menu, greyed tokens, _defeated skipping in next_turn. New suite tools/test_death.gd; 39 suites green.
<!-- SECTION:FINAL_SUMMARY:END -->
