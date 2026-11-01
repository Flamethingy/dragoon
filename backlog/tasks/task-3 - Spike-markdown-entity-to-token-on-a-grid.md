---
id: TASK-3
title: 'Spike: markdown entity to token on a grid'
status: In Progress
assignee:
  - '@Mochi'
created_date: '2026-11-01 11:17'
updated_date: '2026-11-01 11:43'
labels:
  - spike
dependencies: []
documentation:
  - Dragoon Concept
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
First Godot spike (concept: Next steps 4): load one entity markdown file, parse its frontmatter, and show its token on a grid map loaded from an image. Includes the YAML decision: addon, own subset parser, or C#.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 YAML parsing approach decided and recorded
- [ ] #2 Loading an example monster .md yields a Dictionary with frontmatter and body
- [ ] #3 A map image with a grid overlay is shown
- [ ] #4 The entity's token image appears on the grid at its size
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
YAML: own GDScript subset parser (scripts/data/frontmatter.gd) with a headless test. Example campaign files in examples/ (monster + map .md, generated placeholder PNGs). Spike scene scenes/spikes/token_grid.tscn: map image, grid overlay, token at its cell and size.
<!-- SECTION:PLAN:END -->
