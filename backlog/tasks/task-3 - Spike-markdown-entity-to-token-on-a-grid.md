---
id: TASK-3
title: 'Spike: markdown entity to token on a grid'
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-01 11:17'
updated_date: '2026-11-01 11:45'
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
- [x] #1 YAML parsing approach decided and recorded
- [x] #2 Loading an example monster .md yields a Dictionary with frontmatter and body
- [x] #3 A map image with a grid overlay is shown
- [x] #4 The entity's token image appears on the grid at its size
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
YAML: own GDScript subset parser (scripts/data/frontmatter.gd) with a headless test. Example campaign files in examples/ (monster + map .md, generated placeholder PNGs). Spike scene scenes/spikes/token_grid.tscn: map image, grid overlay, token at its cell and size.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
YAML: we use our own GDScript subset parser, `Frontmatter` in `scripts/data/frontmatter.gd`. It handles block and flow maps and lists, lists of maps, typed scalars, quotes, comments and `|`/`>` block strings, with no addon or C#. The decision is recorded in progress.md, and `tools/test_frontmatter.gd` passes. Example campaign: `examples/campaign` has the monsters goblin-chief (medium) and dire-wolf (large), and a map `forest-road.md` with image, grid and a token list. The PNGs are generated placeholders, loaded at runtime (folder has `.gdignore`). Spike: `scenes/spikes/token_grid.tscn` draws the map image with a grid overlay and places the tokens at their cell and creature size (1x1 and 2x2). Mouse wheel zooms, right-drag pans, hovering a token shows its name, HP and AC. Checked visually with `tools/screenshot_scene.gd`. The example fields are provisional until TASK-1.
<!-- SECTION:FINAL_SUMMARY:END -->
