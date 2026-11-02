---
id: TASK-58
title: 'Rules P1: initiative rolling and creature groups'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
updated_date: '2026-11-02 01:35'
labels:
  - rules
  - phase-1
  - combat
dependencies:
  - TASK-53
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- Start combat → initiative is rolled **per creature** by default (Rules module bonus), as `initiative.rolled`.
- Players get a roll prompt, and the DM can roll for absent players.
- **Groups:** when building an encounter (or in the combat dialog), the DM groups creatures (e.g. all goblins). A group shares one roll and one turn slot, and its members are listed under it.
- The order can be edited by dragging. Ties: higher Dex first, then the DM decides.
- Adding a creature mid-combat rolls for it and sorts it in.
- Surprise flag per creature (edition-aware: 2014 skip first turn, 2024 disadvantage on initiative).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Initiative rolled per creature on combat start, players get prompts
- [x] #2 DM can group creatures to share a roll and turn
- [x] #3 Order editable, ties by Dex, late joiners sorted in
- [x] #4 Surprise handled per edition
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design decisions (Mochi):
- Prompts live in the chat ("Roll initiative" link for the owning players; a DM-only "waiting for initiative · roll for them" line). Not stored as events: they're UI, the roll is the event.
- The DM's creatures' initiative roll cards are hidden (DM only); the order itself is public in the tracker (players see the tokens anyway).
- A player's later "initiative" roll is just a roll once their initiative is in (no silent overwrite); the DM drags the order if needed.
- Ties: initiative, then Dex score, then name. After the DM drags once (combat.order_set), the order is "manual": new rolls are put in front of the first entry they beat instead of re-sorting, so the DM's call stays.
- A group rolls with its first member's bonus. Grouping or ungrouping mid-combat re-rolls (bookkeeping is cheap).
- Surprise 2014: next_turn passes surprised creatures in round 1 and says so in the status (the DM can still drag/turn by hand). 2024: the initiative roll gets disadvantage unless the roll says otherwise.
- New events: combat.grouped, combat.ungrouped, combat.order_set, combat.joined, combat.surprise; combat.started has surprised[]; world_state.combat has current, surprised, manual.
- Start/End on the calm table: a "Combat" app button on the default HUD (DM only).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 43fa48d. start_combat rolls per creature (NPCs at once, players prompted in chat, DM rolls for absent players), group_creatures/ungroup, set_order (drag), join_combat for late joiners (also from drop_token), set_surprised with 2014/2024 handling, combat_view sent to players. CombatTracker (scripts/net/combat_tracker.gd) at the top of the table, DM buttons. Replay: groups, manual order, current turn kept with its creature, Dex ties. New suite tools/test_initiative.gd, test_encounters adjusted; 36 suites green.
<!-- SECTION:FINAL_SUMMARY:END -->
