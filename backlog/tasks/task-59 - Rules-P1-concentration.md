---
id: TASK-59
title: 'Rules P1: concentration'
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
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
- [ ] #1 Concentration tracked per caster with icon
- [ ] #2 New concentration replaces old
- [ ] #3 Damage triggers CON save prompt with correct DC
- [ ] #4 Ending removes linked effects
<!-- AC:END -->
