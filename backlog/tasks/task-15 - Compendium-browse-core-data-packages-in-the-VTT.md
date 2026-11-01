---
id: TASK-15
title: 'Compendium: browse core data packages in the VTT'
status: To Do
assignee: []
created_date: '2026-11-01 11:30'
labels:
  - mvp
  - data
  - ui
dependencies: []
documentation:
  - package-format
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The VTT is the viewer for core data (see package-format). Load all packages from `data/packages` at runtime and show a compendium: list per kind with search and filters (source, CR/level, type, school), and a detail view that renders the Markdown text fields (Markdown to BBCode in a RichTextLabel) plus the stat block layout for monsters and spells.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All packages in data/packages load at startup without freezing the UI (4000+ entries)
- [ ] #2 List view per kind with text search and filters (package, CR or spell level, type/school)
- [ ] #3 Monster detail shows the stat block, features and Markdown description
- [ ] #4 Spell detail shows level, components, range, duration and Markdown description
- [ ] #5 Wikilinks in text open the linked entry if it exists
<!-- AC:END -->
