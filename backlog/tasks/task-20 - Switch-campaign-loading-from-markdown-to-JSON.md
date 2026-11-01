---
id: TASK-20
title: Switch campaign loading from markdown to JSON
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-01 13:02'
updated_date: '2026-11-01 13:11'
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
- [x] #1 Campaign loads from data/campaigns/<id>/ JSON files (example campaign converted)
- [x] #2 Session notes are stored in notes.json with real date, session and in-world day
- [x] #3 Lobby, map, party token and event log still work with the JSON campaign
- [x] #4 No runtime code reads campaign .md files anymore
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
- **Loading:** `Campaign` (scripts/net/campaign.gd) reads campaign.json plus one JSON array per kind; entries are addressed as `kind/id`. `Campaign.default_root()` is data/campaigns, and `install_example()` copies examples/campaigns/red-fang there on first host. The table's campaign_dir is empty by default, which means that example.
- **Players and PCs:** logins are the campaign's players (id or name, any case). Unknown or already-connected logins are refused. A PC belongs to the player in its `player` field. PCs without a player can be picked in the lobby, and those picks plus the current map are kept in the campaign's table.json.
- **Events:** events.jsonl lives in the campaign folder, with `by` = the player id (doc-1).
- **Session notes:** SessionNotes stores everything in notes.json `{id n1.., text, real, session, day, time, by, about}`. It writes atomically (temp file, then rename), and headings use the display names from campaign.json (dm → the DM's name).
- **Grid and old files:** TokenGrid lost its .md file mode and only shows data. examples/campaign and the spike scenes (token_grid.tscn, net_table.tscn) are removed; scenes/table.tscn is the table. Frontmatter stays for importers; its test uses tools/fixtures/*.md. secrets.gd is no longer used by runtime code; TASK-18 replaces it.
- **Tests:** tools/test_net_table.gd runs on a copy of the example (Borin made free for picking) and covers lobby, map, party token, rejoin, notes and host restart. tools/test_session_notes.gd was rewritten for notes.json. All 7 test scripts pass, and tools/screenshot_table.gd was updated.
<!-- SECTION:FINAL_SUMMARY:END -->
