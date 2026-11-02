---
id: TASK-64
title: 'Rules P2: feature uses and rests (short rest hit dice, long rest)'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
updated_date: '2026-11-02 02:17'
labels:
  - rules
  - phase-2
dependencies:
  - TASK-51
  - TASK-53
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- The feature `uses` text (1,219 parsed lines: "1/Day", "3/Day each", "Recharge 5-6", "Recharges after a Short or Long Rest") becomes `{max, reset}`. Uses are tracked with `resource.used/restored` and shown as pips on the action button.
- Hit dice per class level as a resource.
- **Short rest dialog** per character: spend hit dice (roll + CON), heal, and reset the short-rest resources.
- **Long rest** for the whole party with one click: full HP, half the hit dice back, slots, uses, exhaustion −1 (edition-aware). It writes `rest.taken` and advances the timeline clock (`time.advanced`).
- Item charges ("at dawn") use the same model.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 uses parsed into max/reset and tracked as resources with pips
- [x] #2 Hit dice resource and short rest dialog
- [x] #3 Party long rest restores per rules and advances the clock
- [x] #4 Dawn resets for item charges
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices (Mochi):
- Resource ids: class resources keep their ids; feature uses are "feature.<id>", hit dice "hit_dice.d<sides>", item charges "charges.<item ref>". NetTable.resources_of(sheet), which is also sheet._resources.
- "N/Day" resets on a long rest; "Recharges after a Short or Long Rest" on a short rest. "Recharge 5-6" stays the turn roll from TASK-63.
- With Auto resources, a use is spent together with its attack or save action. With none left it is used anyway and the DM is told (warn, never block).
- Short rest: per character, from the sheet panel (dialog "ShortRest" with a spinner per hit die). Each die is rolled + CON (at least 0), healing stops at max HP, and short-rest resources come back. Event rest.taken {kind: short, hp, hit_dice, restores}.
- Long rest: the DM's link in the sheet panel or NetTable.long_rest(refs = all characters). It gives full HP; hit dice back by edition (2014 half, at least 1, biggest dice first; 2024 all); slots and uses back; exhaustion −1; then advance_clock(8 h).
- Item charges are not reset by the long rest. They come back when the clock passes 06:00 (they regain their formula, e.g. 1d6+1, with a DM line).
- Item charges are parsed from descriptions ("has 7 charges … regains 1d6 + 1 … at dawn"), or taken from an explicit charges field.
- Fixed along the way: feature names with a "/" ("Battle Cry (1/Day)") were mistaken for catalog refs (new _is_ref).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Uses and rests (commit 7731196): resources with pips and links on the sheet, spending with actions, a short rest dialog, the party long rest with the clock, and dawn charges. Test tools/test_rests.gd; suite 44/44 green.
<!-- SECTION:FINAL_SUMMARY:END -->
