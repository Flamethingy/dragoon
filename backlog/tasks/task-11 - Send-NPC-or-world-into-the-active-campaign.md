---
id: TASK-11
title: Send NPC or world into the active campaign
status: To Do
assignee: []
created_date: '2026-11-01 11:17'
labels:
  - mvp
  - data
dependencies:
  - TASK-6
documentation:
  - Dragoon Concept
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MVP (concept: Campaign layers): the DM sends a single core/world entity or a whole world into the active campaign. This creates a campaign copy that remembers its origin and then drifts freely. Pulling later upstream changes is a separate, deliberate action (not in MVP).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 DM can send one entity or a whole world folder into the campaign
- [ ] #2 The campaign copy stores its origin (layer + path)
- [ ] #3 Changing the core/world original does not change the campaign copy
- [ ] #4 Two campaigns can hold different versions of the same character
<!-- AC:END -->
