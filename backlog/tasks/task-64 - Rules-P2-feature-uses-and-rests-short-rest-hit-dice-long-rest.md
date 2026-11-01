---
id: TASK-64
title: 'Rules P2: feature uses and rests (short rest hit dice, long rest)'
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
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
- [ ] #1 uses parsed into max/reset and tracked as resources with pips
- [ ] #2 Hit dice resource and short rest dialog
- [ ] #3 Party long rest restores per rules and advances the clock
- [ ] #4 Dawn resets for item charges
<!-- AC:END -->
