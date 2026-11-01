---
id: TASK-8
title: 'Session lobby: DM host, players join'
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-01 11:17'
updated_date: '2026-11-01 12:37'
labels:
  - mvp
  - network
dependencies:
  - TASK-5
documentation:
  - Dragoon Concept
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MVP: a simple start screen where the DM hosts a campaign session and players join over the network and pick their PC. The host only sends each player what they may see; DM-only sections are stripped before sending.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 DM can host with a chosen port; players join by address
- [x] #2 Players pick their PC on joining
- [x] #3 Disconnect and rejoin work without restarting the host
- [x] #4 DM-only content never reaches player clients
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Start screen in scenes/table.tscn (TableUI): the DM hosts a campaign folder on a chosen port; players join by address with their name. Names must be unique; a refused player goes back to the start screen. Players pick their PC from cards (portrait, name, class), and taken PCs are greyed out and refused by the host. Who plays whom is kept by name in <campaign log dir>/table.json. After a disconnect a player rejoins with the same name and gets their PC back at its last position, with images from the disk cache; the host keeps running. A restarted host also continues. DM-only content: players never get entity bodies, only whitelisted fields (Campaign.token_view: name, size, type, image hash; hp/ac/class only for their own PC), and assets only for images they may see. Secrets (scripts/net/secrets.gd) also strips dm/secret/dm_* keys, %% comments %%, > [!dm] callouts and DM/Secret sections, for when bodies are sent later. This marking is a proposal for TASK-1 AC3. Covered by tools/test_net_table.gd. Screenshots: tools/screenshot_table.gd. Not in the project's main scene yet; project.godot has unrelated uncommitted changes.
<!-- SECTION:FINAL_SUMMARY:END -->
