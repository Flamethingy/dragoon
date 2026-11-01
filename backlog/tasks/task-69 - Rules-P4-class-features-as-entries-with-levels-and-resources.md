---
id: TASK-69
title: 'Rules P4: class features as entries with levels and resources'
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:45'
labels:
  - rules
  - phase-4
  - data
dependencies:
  - TASK-64
  - TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
rules-automation.md, section 5.3. Class and subclass features are one Markdown text today, and the level table was lost (it was Dataview).
- Split them into feature entries `{name, class, subclass, level, text, uses, effects}` per heading.
- Recover the levels from the vault's class pages (level table) or with an AI pass as drafts.
- Class resources (Rage, Ki/Focus, Sorcery Points, Bardic Inspiration, Channel Divinity, Second Wind, Action Surge ...) with max per level and reset, from dragoon-core tables.
- Characters get their features automatically from `classes[]` + level, plus manual extras.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Class/subclass features are separate entries with level
- [ ] #2 Class resources with per-level max and reset
- [ ] #3 A character's features follow from classes and level
<!-- AC:END -->
