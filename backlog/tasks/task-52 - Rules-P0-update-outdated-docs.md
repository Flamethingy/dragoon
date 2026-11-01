---
id: TASK-52
title: 'Rules P0: update outdated docs'
status: In Progress
assignee:
  - Tamago
created_date: '2026-11-02 00:43'
updated_date: '2026-11-02 00:47'
labels:
  - docs
  - phase-0
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bring the docs in line with the code (list in rules-automation.md and the docs digest):
- CLAUDE.md: still says markdown/vault program, and the read-first list is missing data-layout, timelines, reveal, doc-1 and rules-automation.
- doc-1: entities as markdown, singular refs (`pc/thalia`), `by: player:anna`, `core:items/...` without a package, storage paths, `entity.sent`.
- data-layout: campaign folders (now timelines).
- Concept: resolved open questions, MVP checkboxes.
- progress.md: next steps.
- import-agent: the DraftReview flow (now drafts in packages).
- Terms: monsters → creatures, PCs/NPCs → characters.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No doc describes markdown entities, campaign folders or DraftReview as current
- [ ] #2 Ref and by formats consistent across docs
- [ ] #3 CLAUDE.md read-first list complete
<!-- AC:END -->
