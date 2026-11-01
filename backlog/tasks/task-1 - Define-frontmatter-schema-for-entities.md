---
id: TASK-1
title: Define frontmatter schema for entities
status: In Progress
assignee: []
created_date: '2026-11-01 11:17'
updated_date: '2026-11-01 11:30'
labels:
  - decision
  - data
dependencies: []
documentation:
  - Dragoon Concept
  - package-format
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Agree on the YAML frontmatter schema for monsters, NPCs, PCs, places and items (concept: Data model, Next steps 2). Write it down while importing the campaign into the vault so loader, sheets and future import agents share one schema. Also decide how DM-only secrets are marked (section marker or separate file).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Schema doc in backlog/docs lists required and optional fields per entity type
- [ ] #2 Wikilink fields (faction, location) and token/size fields are defined
- [ ] #3 Marking of DM-only secrets is decided and documented
- [ ] #4 At least one example file per entity type exists
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-01: Core data decision: JSON source packages (one per book), Markdown text fields, viewer in the VTT. Monster and spell schemas are defined in [[package-format]]; `tools/import_obsidian.py` converted the Obsidian DnD5e vault into 33 packages (2160 monsters, 1272 spells, ~660 other entries). Still open: schemas for the world/campaign layers (NPCs, PCs, places) and how DM-only secrets are marked.
<!-- SECTION:NOTES:END -->
