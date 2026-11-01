---
id: TASK-70
title: 'Rules P4: weapons and AC from inventory, attunement'
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:45'
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
- [ ] #1 Equipped weapons become attacks with correct to-hit/damage
- [ ] #2 AC computed from equipped gear
- [ ] #3 Attunement warning
- [ ] #4 Ammunition counter optional
<!-- AC:END -->
