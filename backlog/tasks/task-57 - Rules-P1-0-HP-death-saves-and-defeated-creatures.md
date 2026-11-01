---
id: TASK-57
title: 'Rules P1: 0 HP, death saves and defeated creatures'
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
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
- [ ] #1 0 HP applies Unconscious and enables death saves on the character's turn
- [ ] #2 Damage at 0 counts as failures, healing resets
- [ ] #3 Nat 20 / 3 failures handled
- [ ] #4 Defeated creatures marked and skipped in initiative
<!-- AC:END -->
