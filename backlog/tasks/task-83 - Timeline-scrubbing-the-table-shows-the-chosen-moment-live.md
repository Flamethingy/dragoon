---
id: TASK-83
title: 'Timeline scrubbing: the table shows the chosen moment live'
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-02 13:31'
updated_date: '2026-11-02 14:05'
labels:
  - timeline
  - feature
dependencies:
  - TASK-81
  - TASK-82
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Moving the timeline cursor back changes the table in real time, so everyone can watch what happened (Nico 2026-11-02).

- The table shows the state at the cursor: token positions, HP, conditions, items, built with Replay from the effective events up to that moment.
- **Tokens walk the paths they really took** (the move trails in token.moved), forwards and backwards, rather than jumping.
- Map-independent: the map you're on shows its tokens at that time; moments on other maps are visible on the bar (in their colour), and clicking one may switch to that map.
- Each client scrubs on its own; this is purely local and never changes the log.
- A clear "you're in the past" state, with a **Back to now** button and a key.
- **Players can only act in the present:** while their cursor isn't at now, their HUD/actions are locked with a hint. The DM's acting in the past is a separate ticket.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Dragging the cursor shows the table's state at that moment (positions, HP, conditions)
- [x] #2 Tokens animate along their real trails when scrubbing forward and back
- [x] #3 Scrubbing is local to each client and never writes events
- [x] #4 "Back to now" returns to the live state; new live events still arrive while in the past
- [x] #5 Players can't act while not at now (locked HUD with a hint)
- [x] #6 Headless test of state at a moment, trails and the player lock
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit bc00d82.
- **How a past view is built:** the bar's cursor resolves to the last event id of its moment (TimelineBar.cursor_event). NetTable.look_back(id) shows that moment. The host builds `past_view(player, upto, from)` by cutting the effective events at that id (`_effective()`); view_for then reads it for positions, facing, HP, conditions and doors. Players get the same through the request_past / past_shown RPCs.
- **Fog of war:** a fogged past view shows what the player's tokens saw then, and nothing new is explored.
- **On screen:** TokenGrid.show_past puts the past tokens in an overlay. The live tokens stay hidden underneath and keep getting live updates, so the host's move checks never see the past.
- **Paths:** token.moved now stores the trail. `_paths_between` joins the moves between two moments; going back reverses them, old moves fall back to a straight line, and the party walks once. Past tokens walk square by square, at most ~1.5 s.
- **Lock:** while looking back, grid.locked blocks drag, steps, selection and the token menu. The HUD is dimmed and blocked with a hint, and the host refuses moves of peers looking back and of the DM (acting in the past comes with TASK-85). Now / Home brings everyone back.
- **Map change** while looking back shows the new map at that moment.
- **Test:** tools/test_look_back.gd; the full suite (60) passes.
- **Not yet:** clicking a moment on another map doesn't switch maps; combat tracker and sheets stay live.
<!-- SECTION:FINAL_SUMMARY:END -->
