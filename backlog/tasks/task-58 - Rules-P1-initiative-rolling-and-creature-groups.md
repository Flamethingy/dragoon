---
id: TASK-58
title: 'Rules P1: initiative rolling and creature groups'
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
- Start combat → initiative is rolled **per creature** by default (Rules module bonus), as `initiative.rolled`.
- Players get a roll prompt, and the DM can roll for absent players.
- **Groups:** when building an encounter (or in the combat dialog), the DM groups creatures (e.g. all goblins). A group shares one roll and one turn slot, and its members are listed under it.
- The order can be edited by dragging. Ties: higher Dex first, then the DM decides.
- Adding a creature mid-combat rolls for it and sorts it in.
- Surprise flag per creature (edition-aware: 2014 skip first turn, 2024 disadvantage on initiative).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Initiative rolled per creature on combat start, players get prompts
- [ ] #2 DM can group creatures to share a roll and turn
- [ ] #3 Order editable, ties by Dex, late joiners sorted in
- [ ] #4 Surprise handled per edition
<!-- AC:END -->
