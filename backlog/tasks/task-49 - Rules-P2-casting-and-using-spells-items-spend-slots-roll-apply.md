---
id: TASK-49
title: 'Rules P2: casting and using spells/items (spend slots, roll, apply)'
status: To Do
assignee:
  - Mochi
created_date: '2026-11-01 23:41'
updated_date: '2026-11-02 00:44'
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
- [ ] #1 Casting spends the chosen slot (upcast possible), warns when empty
- [ ] #2 Consumable items and charges are spent
- [ ] #3 Attack/save flows run for the spell or item
- [ ] #4 Concentration handled via TASK-59
<!-- AC:END -->
