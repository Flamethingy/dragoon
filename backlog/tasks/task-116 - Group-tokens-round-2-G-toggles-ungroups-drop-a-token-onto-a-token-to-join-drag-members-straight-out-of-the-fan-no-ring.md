---
id: TASK-116
title: >-
  Group tokens, round 2: G toggles (ungroups), drop a token onto a token to
  join, drag members straight out of the fan (no ring)
status: Done
assignee: []
created_date: '2026-11-05 02:13'
updated_date: '2026-11-05 02:40'
labels:
  - map
  - tokens
  - movement
dependencies:
  - TASK-115
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-05, feedback on the token groups (TASK-115, `GroupStack`):

1. **G toggles:** select a group token and press **G** to **ungroup** it (like "Ungroup all": everyone stays in formation). With 2+ single tokens selected, G groups them as before. With a mix (a group plus single tokens), G adds the singles to the group.
2. **Drop a token onto a token to group, without Alt:**
   - drag a token onto another token and let go: it **joins** as a group member;
   - onto a single token: a new group forms (the target leads);
   - onto a group token: it joins that group.
   - While hovering over a target, a small "+" / highlight on the target shows that letting go groups them.
   - Same permissions as before (players only their own tokens, no groups during combat). During combat or without permission it's a normal move, or not allowed.
   - *Watch out:* this must not clash with TASK-114 (free drag / path mode). Only letting go **exactly on** a token's square groups; otherwise it's a normal move.
3. **No ring any more:**
   - remove the double-click ring;
   - instead, when hovering over the group token the members fan out above it (as now), and **hovering over a single member in the fan** gives it a small **grow animation** (scale up ~1.15 with easing), so you can tell it can be grabbed;
   - you drag a member **straight out of the fan**, and it lands where it's dropped (`group.split` + `token.moved`, as with the ring before);
   - the fan stays open while the mouse is over the group token or the fan (a small grace time so it doesn't collapse when moving between them).

Events stay as they are (`group.formed` / `group.split`). Update tools/test_group_tokens.gd.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 G on a selected group ungroups it; G on 2+ singles groups; a group plus singles adds the singles
- [x] #2 Dropping a token exactly onto another token groups them (or joins the group), without Alt; elsewhere it's a normal move
- [x] #3 The double-click ring is gone
- [x] #4 Hovering a member in the fan grows it slightly; dragging it out splits it off where dropped
- [x] #5 Permissions and combat rule unchanged; test_group_tokens updated and green
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The TASK-116 commit, after 2e22dd3.

- **G toggles** (`TokenGrid._g_key`):
  - a selected group alone → `ungroup_requested` → `split_group` (everyone stays in formation);
  - 2+ singles → group;
  - a group plus singles → they join it, and its leader stays first (`_handle_group` expands groups leader-first).
- **Drop onto a token:**
  - A *free* drag let go exactly on a token (`join_target`: the token under the mouse, not one of the dragged) groups them. The target leads; onto a group token, the dragged ones join it.
  - While over a valid target, a gold ring with a "+" (`GroupStack.JoinHint`) shows.
  - Only if `NetTable.may_group(ids)` allows it: not in combat, and a player only with their own tokens (all members of a group token). Otherwise it's a normal move, which the occupied square refuses.
  - Measured paths (Space, TASK-114) and picked-up ghosts never group, so path mode is unchanged. This was caught by test_token_moves.
- **No ring:**
  - `GroupStack.Ring` and `open_ring` are removed, and the group menu now has only "Ungroup all (G)".
  - A fanned member under the mouse becomes `hot` and grows eased to 1.15 (`grow`, `_process`).
  - Pressing it takes it out (`GroupStack.MemberDrag` follows the mouse, and the face is hidden in the fan meanwhile). Let go elsewhere → `member_out_requested` (`group.split` + `token.moved`); on its group or the fan → nothing; Esc cancels.
- **Fan:** it stays open while over the group token or the fan (`in_fan`), with a 0.3 s grace time after leaving (`close_soon`).
- **Events:** unchanged.
- **Tests:** test_group_tokens is updated and all good:
  - grace and close;
  - hot face grows;
  - grab, let go on its group, follow, drop out;
  - G with a group plus a single, a group alone, two singles;
  - no drop-grouping in combat;
  - the "+" hint, drop onto a single, drop onto a group, a normal move beside a token.

  test_token_moves, test_net_table and test_app are still green. Screenshots: tools/screenshot_groups.gd.
<!-- SECTION:FINAL_SUMMARY:END -->
