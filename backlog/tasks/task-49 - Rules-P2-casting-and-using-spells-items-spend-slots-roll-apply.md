---
id: TASK-49
title: 'Rules P2: casting and using spells/items (spend slots, roll, apply)'
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 23:41'
updated_date: '2026-11-02 02:26'
labels:
  - rules
  - phase-2
dependencies:
  - TASK-48
  - TASK-51
  - TASK-54
  - TASK-55
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What happens when a spell or item is used (Phase 2 of rules-automation.md).
- Casting picks a slot level (default: the spell's level, upcast possible) and spends it via `resource.used`. If no slot is left: a warning, never blocked. Cantrips and rituals spend nothing.
- Items: spend a charge or quantity (`item.lost` for consumables like potions).
- Then it runs what the entry does, using the targeted attack (TASK-54) and save (TASK-55) flows. Once structured spell effects exist (TASK-65), it uses those; until then it uses the text guesses from TASK-48 (clickable dice).
- Concentration spells hand over to TASK-59.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Casting spends the chosen slot (upcast possible), warns when empty
- [x] #2 Consumable items and charges are spent
- [x] #3 Attack/save flows run for the spell or item
- [x] #4 Concentration handled via TASK-59
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices (Mochi):
- HUD spell button → CharacterHud.cast_menu: a cantrip, or a spell with only one valid choice, casts right away. Otherwise a "CastMenu" popup lists the levels that have slots (upcast) plus "As a ritual" if the spell allows it.
- NetTable.cast(ref, spell, level, ritual) routes by Rules.spell_kind: "spell attack" text → the attack bar (attack); a save effect → the attack bar (save); anything else → use_action (posted in the chat as before). The slot level travels in the attack bar's opts.
- The host spends the slot (_cast_costs) when automation resources = Auto: resource.used spell_slots.<level>. With no slot left it casts anyway and the DM gets a line. Cantrips and rituals cost nothing. Concentration spells call _handle_concentrate (TASK-59).
- Spell attacks: Rules.spell_attack_of (spell attack bonus, damage parsed from the entry/text, ranged flag) in _handle_attack for spells/... refs.
- The casting time sets the action pip (bonus/reaction/action).
- Items: charges ("charges.<item>") if it has any, else consumables (potion, scroll, ammunition, consumable) lose one via item.lost. A potion's healing roll heals its drinker (Auto damage).
- Healing spells on other targets still only roll into the chat. Upcast damage scaling is TASK-68.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Casting and using (commit 67df1ca): slot choice with upcast and ritual, spending with warnings, spell attack/save through the attack bar, concentration handover, item charges/consumables, potion healing. Test tools/test_casting.gd; test_character_hud updated (the slot is now spent); full suite green (45).
<!-- SECTION:FINAL_SUMMARY:END -->
