---
id: TASK-53
title: >-
  Rules P1: dragoon-core package and Rules module (derived stats, edition, house
  rules)
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:43'
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
- [ ] #1 dragoon-core package with conditions (both editions), damage types, weapon/armor tables, level tables
- [ ] #2 Rules module computes all derived stats; stored values act as visible overrides
- [ ] #3 World setting for edition and house rules (crit rule on by default for our worlds)
- [ ] #4 Sheet, HUD and dice use the Rules module
<!-- AC:END -->
