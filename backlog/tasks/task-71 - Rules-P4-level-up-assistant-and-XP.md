---
id: TASK-71
title: 'Rules P4: level-up assistant and XP'
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:45'
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
- [ ] #1 Level-up dialog covers HP, features, slots, ASI/feat, spells, subclass
- [ ] #2 XP awards or milestone setting
- [ ] #3 All changes are events
<!-- AC:END -->
