---
id: TASK-13
title: Party token group on the world map
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-01 11:18'
updated_date: '2026-11-01 12:39'
labels:
  - mvp
  - map
dependencies:
  - TASK-7
  - TASK-9
documentation:
  - Dragoon Concept
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MVP (concept: World map and party groups): on the world map party members are grouped into one token. Dragging it moves everyone while still logging a travel event per member. Splitting and merging groups can follow later.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Party members appear as one group token on the world map
- [x] #2 Moving the group logs one travel event per member
- [x] #3 Entering a local map shows the members as individual tokens
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Maps with `kind: world` (a provisional frontmatter field) show every claimed PC as one party token, with the image from `party_token` and the name "Party: Aria Windrunner, Borin Stoneshield". The token sits where its members are (from the log) or at `party_start`. Any party member or the DM may drag it, and players outside the party are refused. NetTable._handle_party_move logs one token.moved per member with data.group = "party" (the field from the doc-1 event format), so each character's own timeline stays complete. Local maps show the members as individual tokens at their own positions on that map, and returning to the world map puts the party where it travelled to. Example: examples/campaign/maps/world.md ("The Westmarch") with tokens/party.png. Covered in tools/test_net_table.gd; screenshot table_world.png from tools/screenshot_table.gd. Splitting and merging groups, and auto-logged arrivals, come later (concept).
<!-- SECTION:FINAL_SUMMARY:END -->
