---
id: TASK-52
title: 'Rules P0: update outdated docs'
status: Done
assignee:
  - Tamago
created_date: '2026-11-02 00:43'
updated_date: '2026-11-02 00:49'
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit c971d24.
- CLAUDE.md: describes JSON as the data format and the VTT as the editor. The read-first list is complete (data-layout, timelines, doc-1, reveal, rules-automation, import-agent), plus a short glossary (creatures, characters, world, timeline).
- doc-1: entities are JSON entries, refs are plural (characters/..., creatures/...), `by` is the player id, refs to core data carry the package (core:5e-core-rules/items/...).
- data-layout: core / world / timeline layers with the world folder layout, and the schema updated to characters + creatures (TASK-43), drafts, origin and timeline.json.
- Concept: resolved open questions and MVP checkboxes marked.
- import-agent: the review step now describes drafts in the package.
- progress.md: new status entries and next steps.
<!-- SECTION:FINAL_SUMMARY:END -->
