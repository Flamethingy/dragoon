---
id: TASK-55
title: 'Rules P1: save-based actions (DC, half on save, bulk saves, save prompts)'
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
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
- [ ] #1 Save-based features roll saves per target (bulk for creatures, prompt for players)
- [ ] #2 Fail/success damage incl. half on save applied as events
- [ ] #3 DC comes from feature data or the caster's spell DC
<!-- AC:END -->
