---
id: TASK-54
title: 'Rules P1: targeted attacks with hit vs AC, crits, damage types, auto-apply'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
updated_date: '2026-11-02 01:40'
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
rules-automation.md, "Attacks and damage".
- Attack flow: pick an action, then click target tokens (one or several), then roll. The roll card shows per target: hit/miss vs AC, natural 20/1, and damage.
- **Crit house rule:** maximum damage dice + a normal roll, modifiers once (world setting from TASK-53).
- Damage types: resistance halves, immunity makes it 0, vulnerability doubles. The card shows "9 → 4 (resistant)".
- **Results apply right away** (`hp.changed` per target, Nico's decision). Undo button on the card and in the log.
- Cover toggle (+2 / +5) and an adv/dis toggle on the card, applied before the roll.
- Multiattack: one button rolls the listed attacks in a row.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Attacks take targets and compare to AC per target
- [x] #2 Crits use max dice + roll
- [x] #3 Resistance/immunity/vulnerability applied and shown
- [x] #4 Damage applies immediately as events; undo works from the card
- [x] #5 Multiattack button
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design decisions (Mochi):
- Flow: a sheet's attack link opens a small attack bar at the bottom ("Scimitar: click the targets"); clicks on tokens toggle targets (red ring), then Roll. No prefill from the selection (the DM's selection is often their own active token, which surprised in tests).
- One to-hit roll per target (5e: each target is its own attack roll), all on one card.
- Advantage: the bar's "Conditions decide" default combines the attacker's (poisoned...) and the target's (restrained, prone, invisible...) flags; Normal/Advantage/Disadvantage on the bar wins. Melee/ranged nuance of prone is not modelled (DM toggles it).
- Cover is a manual toggle (+2 / +5) added to the AC, per decision 4. No flanking (house rule off).
- Damage applies right away on Auto (decision 1), hp.changed by the DM; Undo on the card undoes those events (DM only). Assist: an "apply N" link per target; Off: just the card.
- The card does not show the target's AC number (players shouldn't learn monster ACs from it); the event data keeps it for the DM.
- Multiattack: parsed from the creature's "Multiattack" feature text ("one with its Bite and one with its Claws", "two attacks with its Scimitar", "three Bite attacks"); all its attacks go at the same target(s).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 3275e75. NetTable.attack / request_attack / _attack_card with per-target hit vs AC+cover, nat 20/1, condition-based advantage, crit by the world's rule, Rules.damage_after (resistant/immune/vulnerable) and Rules.cover_bonus; Auto applies hp.changed at once with undo_card, Assist gives apply_card links. Dice.attack_of and Dice.multiattack; sheet Multiattack/attack links; TableUI attack bar with target picking (TokenMarks red ring), cover and adv toggles. New suite tools/test_attacks.gd; 37 suites green.
<!-- SECTION:FINAL_SUMMARY:END -->
