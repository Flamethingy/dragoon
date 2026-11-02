---
id: TASK-74
title: 'Rules P5 (later): summons, wild shape and polymorph'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:45'
updated_date: '2026-11-02 03:38'
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
- Summon spells and features place a linked creature token from the compendium (owner = caster, removed when the effect ends).
- Wild shape / polymorph swaps the active sheet to the beast's stat block while keeping the character's own mental stats and features where the rules say so. It returns on 0 HP (2014: leftover damage carries over) or when ended.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Summons place a linked creature token owned by the caster, removed when the effect ends
- [x] #2 Wild Shape / Polymorph swap to the beast's stat block, keeping what the rules keep
- [x] #3 Back at 0 HP (2014: leftover damage carries over) or when ended
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices (bookkeeping, not decisions; warn, never block):
- Summon = a timeline copy of the compendium creature: name "Wolf (Borin)", owners = the caster's players, attitude = the caster's side. It goes on the nearest free square next to the caster and joins a running combat (rolls initiative).
- A summon ends when the caster's concentration on that spell ends, at 0 HP (it vanishes instead of being marked dead), or via Dismiss on its sheet: combat.left plus token.removed. Durations without concentration end by hand. Summons count as owned tokens but never as party members/PCs (view_for and _pc_of now only take characters/).
- Forms are events (form.assumed / form.ended); sheet_for overlays the beast (Rules.form_sheet). Wild Shape: the beast's STR/DEX/CON, AC, speed, senses, size, defences and actions; the character keeps INT/WIS/CHA, proficiencies and class features. Polymorph: all statistics, no features or spells of its own.
- HP: 2014 forms (and Polymorph) have their own HP. At 0 the character returns and leftover damage carries over. 2024 Wild Shape gives temp HP = druid level (2024 Polymorph: the beast's HP as temp HP) and ends at 0 HP.
- The beast's attacks are resolved from the catalog onto the attack bar. A beast's Multiattack isn't resolved yet (its features live in the packages).
- Wild Shape: the CR limit (2/4/8 → 1/4, 1/2, 1; Moon: 1, then level/3) and the type are only warned about. A use of wild_shape is spent (Auto). Polymorph with a concentration source ends with the caster's concentration.
- Sheet: "Shape" line with Wild Shape... / Polymorph... / Summon... pickers (filtered list, CR shown as 1/4), "Back to own shape", and "Dismiss" on a summon. The token picture doesn't change yet.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Rules: wild_shape_cr, cr_of, cr_text, form_sheet. Replay: form.assumed / form.ended, hp.changed with form:true goes to the form's HP, world_state combat.left. Timeline.owners includes created creatures with owners. NetTable: summon / request_summon / _handle_summon, _free_cell_near, dismiss / _dismiss, summons_of; assume_form / request_form / _handle_form, end_form / _end_form, _handle_form_hp (carry-over), _form_attacks; hooks in end_concentration (summons, polymorphs) and _after_hp (summon at 0 HP, 2024 form at 0 HP); sheet_for overlay and _form. SheetPanel: Shape line, creature_picker. Test: tools/test_forms.gd (54/54 green). Commit 91801cb.
<!-- SECTION:FINAL_SUMMARY:END -->
