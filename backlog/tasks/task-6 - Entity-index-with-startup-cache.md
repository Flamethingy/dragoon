---
id: TASK-6
title: Entity index with startup cache
status: To Do
assignee: []
created_date: '2026-11-01 11:17'
labels:
  - mvp
  - data
dependencies:
  - TASK-1
  - TASK-3
documentation:
  - Dragoon Concept
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Parse all campaign entity files once at startup into an in-memory index (by name, type, wikilink); a cache file means later starts only re-parse changed files (concept: Performance and data transfer). Body markdown is converted to BBCode for the info panel.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All .md files in the campaign folder are indexed at startup
- [ ] #2 Second start only re-parses changed files (cache)
- [ ] #3 Wikilinks [[Name]] resolve to indexed entities
- [ ] #4 Body markdown renders in a RichTextLabel info panel
<!-- AC:END -->
