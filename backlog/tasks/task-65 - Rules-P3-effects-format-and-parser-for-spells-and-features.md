---
id: TASK-65
title: 'Rules P3: effects format and parser for spells and features'
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:45'
labels:
  - rules
  - phase-3
  - data
dependencies:
  - TASK-53
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
rules-automation.md, section 5.2.
- Define the optional `effects` list (roll attack/save/check, damage, heal, apply condition with duration and save_ends, modifier, resource, area, scaling) in package-format.md and the Schema. The text stays the source of truth.
- Regex parser in tools/import_obsidian.py (and the import agent) for the clear cases:
  - spell attack, save ability + DC/"spell", half on save, damage dice and types
  - area shape + size (sphere/radius, cone, line, cube, cylinder)
  - "At Higher Levels" dice per slot, cantrip scaling
  - conditions ("must succeed ... or be frightened"), durations
- Report the coverage per kind; entries without effects keep the text fallback.
- Effects editor with presets in the entry editor.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 effects format documented and in the Schema
- [ ] #2 Parser fills effects for spells and creature features; coverage reported
- [ ] #3 Effects editor in the entry editor
- [ ] #4 Audit passes
<!-- AC:END -->
