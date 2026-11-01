---
id: TASK-1
title: Define entity schema (JSON) for world and campaign
status: In Progress
assignee: []
created_date: '2026-11-01 11:17'
updated_date: '2026-11-01 13:02'
labels:
  - decision
  - data
dependencies: []
documentation:
  - Dragoon Concept
  - package-format
  - reveal-visibility
  - data-layout
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico decided on 2026-11-01: JSON everywhere, the VTT is the editor (see [[data-layout]]). Core schemas are in [[package-format]]. Still to define: fields per world/campaign kind (PC, NPC, place, faction, map, lore, note), using the same field names as the packages. DM secrets are decided ([[reveal-visibility]]).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Marking of DM-only secrets is decided and documented
- [ ] #2 data-layout.md lists required and optional fields for PC, NPC, place, faction, map, lore and note
- [ ] #3 Link fields (faction, location, owner) and token/size/map grid fields are defined
- [ ] #4 Example campaign in JSON (replaces examples/campaign/*.md) with at least one entry per kind
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-01: Core data decision: JSON source packages (one per book), Markdown text fields, viewer in the VTT. Monster and spell schemas are defined in [[package-format]]; `tools/import_obsidian.py` converted the Obsidian DnD5e vault into 33 packages (2160 monsters, 1272 spells, ~660 other entries). Still open: schemas for the world/campaign layers (NPCs, PCs, places) and how DM-only secrets are marked.

2026-11-01: AC3 decided differently from Mochi's marker proposal: per-passage visibility with `<reveal id for>` tags, reveals during play as `reveal.changed` events, colors from each account (DM too, no fixed red). See [[reveal-visibility]]; implementation in TASK-18 and TASK-19.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @Mochi
created: 2026-11-01 11:45

---

FYI from TASK-3: the example entities in `examples/campaign/` (monster and map .md) use provisional fields: type, name, source, hp, ac, stats, token, size, faction, actions, and grid/tokens for maps. Please adjust them to the schema you settle on. `Frontmatter` (scripts/data/frontmatter.gd) parses the YAML subset: block and flow maps and lists, lists of maps, scalars, comments, and | and > block strings.

---

author: @Mochi
created: 2026-11-01 12:37

---

Proposal for AC3 (DM-only secrets), already implemented in scripts/net/secrets.gd for the table (TASK-8). Frontmatter: keys `dm`, `secret`, `secrets` and anything starting with `dm_` (e.g. `dm_notes:`). Body: Obsidian `%% comments %%`, callouts `> [!dm]` / `> [!secret]`, and sections whose heading starts with "DM" or "Secret" (up to the next heading of the same level). This is easy to change once you decide. Also new provisional fields in the examples: `type: pc` (examples/campaign/pcs/), `class`, and `party_start: [x, y]` on maps.

---
<!-- COMMENTS:END -->
