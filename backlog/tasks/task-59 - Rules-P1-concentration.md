---
id: TASK-59
title: 'Rules P1: concentration'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
updated_date: '2026-11-02 01:53'
labels:
  - rules
  - phase-1
  - combat
dependencies:
  - TASK-55
  - TASK-56
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- Casting a concentration spell marks the caster as concentrating on it (icon on token and HUD).
- A second concentration spell ends the first, with a confirm.
- Damage to a concentrating creature → a CON save prompt for the owner (DC max(10, half the damage)). A failure ends it.
- Incapacitated / 0 HP ends it.
- Ending concentration removes the effects linked to it (conditions, buffs from that spell).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Concentration tracked per caster with icon
- [x] #2 New concentration replaces old
- [x] #3 Damage triggers CON save prompt with correct DC
- [x] #4 Ending removes linked effects
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design decisions (Mochi):
- Concentration is the "concentrating" condition marker with data {spell, name}; replay keeps sheet.concentration. The token shows the marker disc, the HUD portrait a "◆ Spell" label, the sheet "Concentrating (Spell)".
- The confirm for a second concentration spell happens on the caster's own screen (concentration_confirm signal → ConfirmationDialog). The host never asks: a request that arrives replaces the old one (the player already said yes).
- Several damage instances before the save is rolled: one pending save with the highest DC (bookkeeping, not a pile of prompts).
- Automation: Off = nothing tracked; Assist = the save is asked, a failure leaves an "end concentration" link; Auto = a failure ends it.
- Linked effects = conditions put on by that spell's save action (data.source {caster, spell}); buffs (active effects) will link the same way in Phase 2.
- Incapacitated, paralyzed, petrified, stunned, unconscious, dead (and conditions flagged breaks_concentration in 2024) end it.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 737ee09. concentrate/request_concentrate/_handle_concentrate, end_concentration (removes linked conditions by source), _concentration_check on damage (DC max(10, half), 2024 cap 30) with prompts for players and instant saves for DM creatures, answer_concentration, incapacitation and 0 HP end it; save actions of concentration spells link their conditions. HUD/sheet indicators, confirm dialog. New suite tools/test_concentration.gd; 40 suites green.
<!-- SECTION:FINAL_SUMMARY:END -->
