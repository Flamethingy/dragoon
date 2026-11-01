---
id: TASK-54
title: 'Rules P1: targeted attacks with hit vs AC, crits, damage types, auto-apply'
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
labels:
  - rules
  - phase-1
  - combat
dependencies:
  - TASK-53
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
rules-automation.md, "Attacks and damage".
- Attack flow: pick an action, then click target tokens (one or several), then roll. The roll card shows per target: hit/miss vs AC, natural 20/1, and damage.
- **Crit house rule:** maximum damage dice + a normal roll, modifiers once (world setting from TASK-53).
- Damage types: resistance halves, immunity makes it 0, vulnerability doubles. The card shows "9 → 4 (resistant)".
- **Results apply right away** (`hp.changed` per target, Nico's decision). Undo button on the card and in the log.
- Cover toggle (+2 / +5) and an adv/dis toggle on the card, applied before the roll.
- Multiattack: one button rolls the listed attacks in a row.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Attacks take targets and compare to AC per target
- [ ] #2 Crits use max dice + roll
- [ ] #3 Resistance/immunity/vulnerability applied and shown
- [ ] #4 Damage applies immediately as events; undo works from the card
- [ ] #5 Multiattack button
<!-- AC:END -->
