---
id: TASK-71
title: 'Rules P4: level-up assistant and XP'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:45'
updated_date: '2026-11-02 03:22'
labels:
  - rules
  - phase-4
dependencies:
  - TASK-69
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- Level up dialog per character: choose the class (multiclass), HP (roll or average + CON), new features of that level, new slots, ASI or feat, new spells known/prepared, subclass choice at its level. It writes `level.gained` and `sheet.changed` events.
- XP: `xp.awarded` event (encounter XP from CR via dragoon-core) or milestone levelling (world setting).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Level-up dialog covers HP, features, slots, ASI/feat, spells, subclass
- [x] #2 XP awards or milestone setting
- [x] #3 All changes are events
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices (bookkeeping, not decisions; warn, never block):
- The dialog never picks for the player: the subclass defaults to "choose later", ASI stays empty unless chosen, HP defaults to the average (rolling is one click).
- Levelling without enough XP or a milestone is allowed; the DM gets a line.
- Max HP = the entry's hp + the HP gained from level.gained events (`hp_max_gain`), so the file stays the base.
- Encounter XP: at the end of a combat (levelling "xp"), the XP of the defeated creatures (0 HP / dead / defeated; by CR or their own xp) is split among the PCs who fought and applied at once (Nico's decision 1: the DM undoes). Milestone worlds get none; grant_level gives a milestone.
- Levelling is a world house rule (Rules page, like crit/flanking): xp / milestone.
- New spells: the dialog reminds casters; picking them stays with the player (drop on the sheet, or the level_up `spells` choice). There are no spells-known tables in dragoon-core yet.
- Feat by ref in a text field (feats/...), which is enough for now; a picker could follow.
- Flaky tests: test_turn_engine had two random checks (a DC 1 save with WIS −1, a 10-try recharge loop), now deterministic. test_character_hud had a sync race, fixed in TASK-68.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Rules: xp_for_level, level_for_xp, xp_of (CR incl. "1/4"), levelling, hit_die, hp_gain, subclass_level (2024: 3), asi_levels, level_up_plan. core.json: house rule "levelling", subclass_levels, asi_levels, attunement_max. Replay: level.gained adds hp_gain (max and current), the subclass, uses up a milestone; xp.awarded; level.granted. NetTable: level_up / request_level_up / _handle_level_up (level.gained plus sheet.changed for stats, feats and spells; a public line), award_xp, grant_level, can_level, catalog_list, level_up_plan (with new feature names and subclasses), _encounter_xp at end_combat, sheet._level. SheetPanel: "Level N" line (XP x / y, Level up, ready) and the LevelUp dialog. Test: tools/test_levelling.gd (52/52 green). Commit 9c87b44.
<!-- SECTION:FINAL_SUMMARY:END -->
