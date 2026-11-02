---
id: TASK-53
title: >-
  Rules P1: dragoon-core package and Rules module (derived stats, edition, house
  rules)
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:43'
updated_date: '2026-11-02 01:09'
labels:
  - rules
  - phase-1
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Foundation of Phase 1 (rules-automation.md, sections 5.1 and 5.4).

**`dragoon-core` package** in git (SRD content is open):
- conditions (15 + exhaustion) with icon, rules text and mechanical flags, per edition (2014/2024)
- damage types, weapon properties, armor table
- proficiency by level, spell slot tables, cantrip scaling, XP by CR

**`Rules` module (GDScript)** computes from sheet + classes + items + active effects:
- ability mods, proficiency, saves, skills (incl. expertise and Jack of All Trades)
- passive Perception/Insight/Investigation, AC, initiative
- spell DC and attack, slot and resource maxima

Stored fields become overrides (shown with a marker). The sheet, HUD, dice and later assistants all use it.

**World settings:**
- rules edition (2014 / 2024 / mixed: an entry's own edition wins)
- house rules, starting with **crit = maximum damage dice + a normal roll**
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 dragoon-core package with conditions (both editions), damage types, weapon/armor tables, level tables
- [x] #2 Rules module computes all derived stats; stored values act as visible overrides
- [x] #3 World setting for edition and house rules (crit rule on by default for our worlds)
- [x] #4 Sheet, HUD and dice use the Rules module
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design decisions (Mochi, in the spirit of "bookkeeping, not decisions"):
- dragoon-core lives in assets/rules/dragoon-core (git, res://), not data/packages: it is SRD, ships with the app and must exist on every machine.
- Rules settings are stored in the world's package.json under "rules" (edition, house_rules, automation); defaults fill gaps (2014, crit max_plus_roll, flanking off). An entry's own "edition" wins over the world's.
- Stored sheet values win over computed ones; derived() marks them as overrides only when they differ from the computed value (the sheet shows a wine-coloured *).
- Conditions only *suggest* advantage/disadvantage (suggested_advantage), they never force a roll.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit f85c4f6. assets/rules/dragoon-core (conditions for both editions with flags, damage types, weapon properties/masteries, SRD weapons and armor, proficiency/slot/XP/encounter tables, cantrip scaling, hit dice, class resources, house rule options) and scripts/rules/rules.gd (Rules: proficiency by level or CR, saves, skills with expertise and Jack of All Trades, passives, initiative, AC from armor, spell DC/attack, slots, resources, hit dice, condition flags, suggested advantage, 2024 exhaustion penalty, crit formula by house rule, derived() with overrides). World setting "rules" in the world package.json, sent to players with the table. Dice, HUD widgets, quick buttons and the sheet panel all use Rules. New suite tools/test_rules.gd; all 34 suites green.
<!-- SECTION:FINAL_SUMMARY:END -->
