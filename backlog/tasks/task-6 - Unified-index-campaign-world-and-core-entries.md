---
id: TASK-6
title: 'Unified index: campaign, world and core entries'
status: To Do
assignee: []
created_date: '2026-11-01 11:17'
updated_date: '2026-11-01 13:02'
labels:
  - mvp
  - data
dependencies:
  - TASK-20
documentation:
  - data-layout
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Originally "parse markdown entities with a startup cache". With JSON everywhere ([[data-layout]]) and the compendium's package_db already loading core packages, this becomes: one index over campaign → world → core, so lookups and wikilinks resolve in that order (a campaign copy of Mira wins over the world original). Cache only if loading gets slow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Campaign, world and core entries are in one index with layer priority campaign > world > core
- [ ] #2 Wikilinks [[Name]] resolve with that priority
- [ ] #3 Loading time measured with all 34 packages + example campaign; cache added only if > 2 s
<!-- AC:END -->
