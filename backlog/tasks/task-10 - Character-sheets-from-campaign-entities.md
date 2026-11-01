---
id: TASK-10
title: Character sheets from campaign entities
status: To Do
assignee: []
created_date: '2026-11-01 11:17'
labels:
  - mvp
  - sheets
dependencies:
  - TASK-6
  - TASK-9
documentation:
  - Dragoon Concept
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MVP: show character sheets built from campaign entity frontmatter in our fixed sheet layout (no settings). Changes such as HP go through the event log instead of overwriting the file.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Clicking a token opens its sheet (stats, HP, AC) and info page
- [ ] #2 Players see their own PC sheet; DM sees all
- [ ] #3 HP and other edits are recorded as events, not written into the .md file
<!-- AC:END -->
