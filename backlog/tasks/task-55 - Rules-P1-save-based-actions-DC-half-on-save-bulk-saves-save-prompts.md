---
id: TASK-55
title: 'Rules P1: save-based actions (DC, half on save, bulk saves, save prompts)'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
updated_date: '2026-11-02 01:44'
labels:
  - rules
  - phase-1
  - combat
dependencies:
  - TASK-54
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Use the parsed `feature.save` ({ability, dc}), which is unused so far.
- Action with a save: pick targets, then each target rolls the save.
  - Creatures: the DM's side rolls them in bulk.
  - Players: a prompt "Dex save DC 15 [Roll]" on their screen. The DM can roll for them after a timeout.
- Damage on fail, half on success when the text says so (parser flag), applied right away per target.
- Conditions named in the effect are applied on a failed save (needs TASK conditions).
- Spell save DC from the Rules module for character spells.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Save-based features roll saves per target (bulk for creatures, prompt for players)
- [x] #2 Fail/success damage incl. half on save applied as events
- [x] #3 DC comes from feature data or the caster's spell DC
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design decisions (Mochi):
- Damage is rolled once for all targets (5e rule), each target saves on its own.
- "The DM can roll for them after a timeout": no automatic timer. The DM sees "waiting for the DEX save DC 13 · roll for them" and decides when (never decide for the table automatically).
- A player can only answer their own creature's prompt, and only once; later answers are ignored.
- Natural 20/1 mean nothing special on saves (RAW).
- Conditions named in the text are put on after a failed save when conditions automation is Auto (Assist just lists them on the card), with the parsed duration ("for 1 minute" = 10 rounds, "until the end of its next turn" = 1 round, ends turn_end).
- Cover on the bar adds +2/+5 to Dex saves only.
- Undo on the card undoes the damage and the conditions it applied.
- A player's late answer becomes its own small card ("Fire Breath: DEX save") instead of rewriting the first card (events are immutable).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit a0030ef. Rules.save_effect (ability, DC from feature or caster spell DC, damage, half, conditions, duration). NetTable.save_action/request_save_action, _save_row (bulk saves for the DM's creatures), save prompts for players and DM "roll for them" (answer_save), undo/apply generalised to save cards incl. conditions. Sheet save-action links, attack bar in "save" mode. New suite tools/test_saves.gd; 38 suites green.
<!-- SECTION:FINAL_SUMMARY:END -->
