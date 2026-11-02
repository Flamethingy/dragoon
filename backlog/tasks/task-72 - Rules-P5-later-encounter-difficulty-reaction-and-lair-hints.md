---
id: TASK-72
title: 'Rules P5 (later): encounter difficulty, reaction and lair hints'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:45'
updated_date: '2026-11-02 03:29'
labels:
  - rules
  - phase-5
  - later
dependencies:
  - TASK-63
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Optional extras from rules-automation.md:
- Encounter difficulty while building an encounter: XP budget from creature CRs vs party levels (2014 thresholds / 2024 budget), shown as easy to deadly.
- Reaction hints for the owning player (Shield, Counterspell, Uncanny Dodge), non-blocking. Off by default.
- Opportunity attack reminder when a token leaves a hostile's reach.
- Massive damage and similar warnings collected here if not done yet.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Encounter difficulty from CR XP vs party levels (2014 thresholds / 2024 budget)
- [x] #2 Reaction hints for the owning player (Shield, Counterspell, Uncanny Dodge), off by default
- [x] #3 Opportunity attack reminder when leaving a foe's reach
- [x] #4 Massive damage warning
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices:
- There is no separate encounter builder: the DM prepares a fight by placing tokens. So the difficulty is computed from the map (characters vs living, non-friendly creatures) and shown to the DM on the "Start combat (Hard)" button (tooltip: XP, adjusted XP, thresholds) and in the tracker head ("Round 2 · Medium", living foes only).
- 2014: XP × the count multiplier, one step up for parties under 3 and one down for 6+. 2024: the plain XP vs the low/moderate/high budget (table added to dragoon-core from the 2024 DMG).
- Hints use the existing automation "reactions" (Off by default; Assist or Auto both only hint, nothing is applied). They go only to the creature's players (a new private log line; the DM sees all), and for monsters to the DM.
- Shield only when +5 AC would actually turn the hit into a miss (not on crits) and a slot ≥1 is left. Uncanny Dodge when the sheet has it (class features from TASK-69 count). Counterspell when a foe casts within 18 m, a slot ≥3 is left and the reaction is free. Opportunity attack when the mover leaves a foe's melee reach (the longest melee attack; "melee or ranged" counts as 1.5 m), noting Disengage. A used reaction (turn economy) stops the hints.
- Massive damage was already warned in TASK-57.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Rules.encounter_difficulty; core.json encounter_budget_2024. NetTable: encounter_difficulty() for the map, _hint (private to owners), _attack_hints (Shield / Uncanny Dodge, hooked into _attack_card), _counterspell_hints (in _cast_costs), _opportunity_hints (in _handle_move), _side, _reach_m, _gap_m, _ready_spell, _has_reaction. table_ui: Start combat (rating) with a tooltip; CombatTracker head shows the rating to the DM. Test: tools/test_hints.gd (53/53 green). Commit 6a7a579.
<!-- SECTION:FINAL_SUMMARY:END -->
