---
id: TASK-20
title: Switch campaign loading from markdown to JSON
status: To Do
assignee: []
created_date: '2026-11-01 13:02'
labels:
  - mvp
  - data
dependencies:
  - TASK-1
documentation:
  - data-layout
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Since the VTT is the editor and everything is JSON ([[data-layout]]), the campaign code still reads `.md` files with frontmatter: `scripts/net/campaign.gd`, `scripts/spikes/token_grid.gd`, `scripts/notes/session_notes.gd` (writes prep.md / session-NN.md) and `res://examples/campaign`. Move them to the campaign folder layout (campaign.json, pcs.json, npcs.json, monsters.json, maps.json, notes.json, events.jsonl, assets/) and convert the example campaign. `scripts/data/frontmatter.gd` is then only needed for importers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Campaign loads from data/campaigns/<id>/ JSON files (example campaign converted)
- [ ] #2 Session notes are stored in notes.json with real date, session and in-world day
- [ ] #3 Lobby, map, party token and event log still work with the JSON campaign
- [ ] #4 No runtime code reads campaign .md files anymore
<!-- AC:END -->
