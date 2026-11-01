---
id: TASK-63
title: 'Rules P2: turn triggers and effect durations'
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
labels:
  - rules
  - phase-2
  - combat
dependencies:
  - TASK-56
  - TASK-58
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- Effects and conditions get durations: rounds, "until start/end of X's next turn", minutes/hours (in-world clock), concentration-linked.
- Turn engine at start/end of each turn:
  - recharge rolls (Recharge 5–6) for creature features
  - "save ends" prompts (save at end of turn)
  - ongoing damage, regeneration (with "unless fire/acid" as a reminder)
  - legendary action counter reset, reaction reset
  - expiring effects
- Expired effects are removed with a log line (undoable), per the table setting.
- Legendary actions/resistances as counters on the creature.
- Lair actions: a reminder at initiative 20.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Durations by round/turn/clock tracked and expiring with a log line
- [ ] #2 Recharge rolls at turn start
- [ ] #3 Save-ends prompts at the right moment
- [ ] #4 Legendary action/resistance counters reset correctly
- [ ] #5 Lair reminder at initiative 20
<!-- AC:END -->
