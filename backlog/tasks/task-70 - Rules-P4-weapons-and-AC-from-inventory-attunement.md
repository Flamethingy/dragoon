---
id: TASK-70
title: 'Rules P4: weapons and AC from inventory, attunement'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:45'
updated_date: '2026-11-02 03:14'
labels:
  - rules
  - phase-4
dependencies:
  - TASK-51
  - TASK-53
  - TASK-54
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- Items get structured data where it matters: weapons (damage dice/type, properties: finesse, versatile, ranged + range, heavy, light, thrown, reach; 2024 mastery), armor (base AC, Dex cap, shield bonus), and +N magic bonuses. Parsed from text and weapon/armor tables in dragoon-core.
- Equipped weapons appear as attack actions on the HUD (to-hit = ability + proficiency + bonus).
- AC is computed from equipped armor + Dex + shield + items (Rules module), and an override is possible.
- Attunement: flag on items, warning beyond 3.
- Optional ammunition counter.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Equipped weapons become attacks with correct to-hit/damage
- [x] #2 AC computed from equipped gear
- [x] #3 Attunement warning
- [x] #4 Ammunition counter optional
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices (bookkeeping, not decisions; warn, never block):
- An item's data is found from: its own fields (weapon/armor/bonus/ac_bonus/attunement override), then the core table by id, the name/type ("+1 Longsword", "Weapon, GreatAxe"), and the text ("functions as a light hammer", "+N bonus to attack and damage rolls", "+N bonus to AC", "requires attunement").
- Magic from an item that needs attunement only counts once it's attuned. A 4th attunement is allowed but shown orange on the sheet, with a DM line.
- Proficiency comes from the sheet's proficiencies plus the class's prof_weapon. With nothing known it counts as proficient (no silent penalty).
- Versatile weapons get a second "(two-handed)" attack when no shield is equipped. Off-hand/light two-weapon fighting is left to the player.
- AC: the stored `ac` stays an override. Heavy armor ignores DEX, even a negative one (bug fixed). Unarmored Defense for Barbarian/Monk.
- Ammunition is a new automation category, Off by default (optional): Auto takes one arrow/bolt per shot; out of ammo = shot anyway plus a DM line. Assist only reminds.
- Equip and attune are item.flagged events, toggled with links in the sheet's inventory.
- 2024 masteries are kept on the attack (mastery), not applied.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Rules.gear / item_info / equipped_gear / weapon_attacks / weapon_proficient / attunement, and armor_ac with magic bonuses, Unarmored Defense and the heavy-armor fix. Replay "item.flagged". Dice._attack_feature uses the sheet's _weapon_attacks; attack_of carries item and ammunition. NetTable: sheet_for adds _gear, _weapon_profs, _weapon_attacks, _attunement and weapon names in _attacks; flag_item / request_flag / _handle_flag; _use_ammunition with automation "ammunition". SheetPanel._gear: inventory with equip/attune links and an attunement count. Test: tools/test_gear.gd (51/51 green). Commit 4ca5323.
<!-- SECTION:FINAL_SUMMARY:END -->
