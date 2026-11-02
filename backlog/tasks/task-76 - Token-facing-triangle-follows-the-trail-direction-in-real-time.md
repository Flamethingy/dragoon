---
id: TASK-76
title: Token facing triangle follows the trail direction in real time
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 01:16'
updated_date: '2026-11-02 08:36'
labels:
  - map
  - tokens
  - feedback
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico's feedback 2026-11-02: when a token moves along its trail, its direction triangle should turn live to point along the current path segment, not only at the end.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The triangle rotates to each segment's direction while the token moves along the trail
- [x] #2 Final facing stays the last segment's direction (or as set)
- [x] #3 Same on all clients
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices:
- During the glide, a tween callback before each step turns the token toward that step (8 directions, the same as WASD).
- The host takes the final facing from the trail's last step (before this it was the straight line from start to end). That facing goes into the log (token.moved `facing`) and token_turned as before.
- Same on all clients: the host passes the trail on with token_moved (a new trail argument). Every screen glides square by square and turns at the same steps; before, only the mover's own screen followed the trail.
- Straight moves (WASD, drag without a plan) and fogged maps (which send whole views) behave as before.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 654a400. TokenGrid: a facing callback per trail step in set_token_cell, and glide_along(). NetTable: _valid_trail; the final facing comes from the last trail step; token_moved RPC carries the trail; the party move sends []. New test tools/test_trail_facing.gd (DM plus a player: facing sequence se → e → ne on both screens, and the log). Tests: 57/57 green.
<!-- SECTION:FINAL_SUMMARY:END -->
