---
id: TASK-115
title: >-
  Group tokens: combine into one group token, move it as one, drag tokens out
  again
status: Done
assignee: []
created_date: '2026-11-05 00:47'
updated_date: '2026-11-05 01:25'
labels:
  - map
  - tokens
  - movement
dependencies:
  - TASK-114
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-05: tokens can be **grouped**, **moved like one token**, and **dragged out again** into their own tokens. The exact look is still open (see the suggestions); until Nico decides, **suggestion A** applies.

**Grouping:**
- select several tokens (Shift-click / box select), then **G** or the right-click menu "Group";
- or drag a token onto another one with Alt held.

**Moving:** the group moves like one token (the TASK drag flow with Space), with the speed of the **slowest** member and difficult terrain for the group's square. On arrival the members keep their formation (positions relative to each other), or stand together on the group's square.

**Splitting:**
- drag a single token out of the opened group, and it becomes its own token again at the drop point;
- right-click "Ungroup" splits everyone up around the group's square.

**Rules:**
- a combat start (initiative) splits the group automatically (or asks);
- players may only group their own tokens; the DM may group all of them;
- events go into the event log (`token.grouped` / `ungrouped`), so undo works.

**Suggestions for the look:**
- **A) Stack token** (recommended): one token with the leader's portrait, the others as small overlapping portraits at the edge (like a stack of cards), plus a number badge "×4". Hovering fans the members out; a double-click opens the group in a ring around the square, and you drag single members out of the ring.
- **B) Party banner:** a token with a flag/banner icon and the group's name ("Party", "Goblin patrol"), with the members listed in the tooltip. Clear for marching groups, but you can't see who is in it.
- **C) Ring of tokens:** the members stay visible as small tokens in a ring on one square, with a shared outline in the group colour. Clearest, but crowded with more than 4–5 members.
- **D) Formation outline:** the tokens stay where they are and get a shared coloured outline / connecting line; they move together and keep their formation. Good for "marching order", no extra token.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Several tokens can be grouped (G / menu) into one group token
- [x] #2 The group moves like one token (slowest speed) and keeps its formation
- [x] #3 Single tokens can be dragged out of the group; Ungroup splits all
- [x] #4 Grouping/ungrouping is in the event log (undo) and synced to all clients
- [x] #5 Headless test: group, move, split
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
"The TASK drag flow" in the description means TASK-114 (free drag, Space to measure, Space to move).

**Decided by Nico (2026-11-05): look A (stack token).** The leader's portrait with the others as small overlapping portraits at the edge, plus a "×N" badge. Hovering fans them out; a double-click opens the ring, and members are dragged out of it.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Look A (stack token), commits 49b0d5b + 010e4a4.

- **Events:** `group.formed` {map, group, members, leader} / `group.split` {map, group, members ([] = all), why}, documented in doc-1 Event-format. `NetTable.groups_on(map)` replays them, so undo (the timeline's undo) works. They are deliberately not `token.*`, so Replay's token positions stay untouched.
- **View:** on non-world maps the grouped members show as one `groups/<id>` token: the leader's picture, the others small at its lower right edge, a ×N badge (`GroupStack`). Hovering fans them out above it. Vision comes from every member's own square. Synced through the normal view / `_send_tables`.
- **Grouping:**
  - **G** with 2+ selected;
  - the right-click menu "Group the N selected";
  - **Alt + drop** one token onto another (that one leads).
  - Players may group only their own tokens; no groups during a combat.
- **Moving:** the group drags like one token (TASK-114 flow) at its slowest member's speed (trail colour). Every member moves by the same offset, keeping the formation: one `token.moved` per member with `group`, and the leader's carries the trail and cost.
- **Splitting:**
  - a double-click opens a ring of the members (names under them); drag one out and it lands where it's dropped (`group.split` + its `token.moved`);
  - the group menu has Ungroup all (everyone stays in formation);
  - Esc / a click beside the ring closes it;
  - `start_combat` splits every group on the map first.
- **Tests:** tools/test_group_tokens.gd (permission, G, faces, event, sync to Ann, hover fan, slowest speed, formation move by a player, ring drag-out, ungroup, undo, combat split, Alt-drop), all good. test_token_moves, test_net_table, test_tokens, test_character_hud, test_quick_search, test_app, test_initiative, test_look_back, test_token_look and test_vision are still green (test_tokens' known quit crash 139 after "all good"). Screenshots: tools/screenshot_groups.gd.
- **Open:** difficult terrain is reckoned for the leader's path only, not per member.
<!-- SECTION:FINAL_SUMMARY:END -->
