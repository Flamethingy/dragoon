---
id: TASK-79
title: Moving through another token's square counts as difficult terrain
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 01:16'
updated_date: '2026-11-02 08:31'
labels:
  - rules
  - map
  - movement
  - feedback
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico's feedback 2026-11-02: when a move passes through another creature's square, that square costs double distance (5e: another creature's space is difficult terrain). The movement pips/ruler (TASK-62) count it. Later, make it a world setting (on/off, maybe only for hostile creatures), together with the rules settings (TASK-60).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Squares occupied by another token cost double movement
- [x] #2 The ruler and remaining movement show the doubled cost
- [x] #3 Warn, never block (fits rules-automation.md)
- [x] #4 World setting to turn it off (can be a follow-up)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
What TASK-73 already covered: painted difficult terrain (one extra square per square entered) in turn_usage and on the move trail. TASK-73 did not count other tokens, and the host only counted the straight line from start to end.

Design choices:
- An occupied square (any size of token, but not the party token) costs one extra square when the trail passes through it. The end square must be free anyway, so it never counts as crowded.
- The host now gets the planned trail with the move (request_move has a path argument). It counts that trail if it is consistent: it starts at the token, ends at the target, and every step is one square. Otherwise it counts the straight line. So going round a creature costs nothing extra.
- The cost is stored on the token.moved event (`cost`), as counted at the time of the move. Later token moves don't change it, and undo or replay stays exact. Old events without `cost` are counted from the straight line, as before.
- It only warns: the move always happens. The trail label turns orange when it goes over the budget.
- World setting (house rule "Moving through creatures"): all (default, 5e) / only hostile creatures / off. Hostile is reckoned by side: party plus friendly NPCs against foes. A player's own trail preview guesses the side from the token kind; the host's count is the one that counts.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit da63f50. Added the house rule crowded_squares (core.json, Rules.crowded_squares). TokenGrid: crowd callable, occupied(), difficult_for() (terrain plus crowded squares), trail_of(). MovePlans counts difficult_for on the trail. NetTable: _crowded / _crowd_side; _move_cost along the sent trail (falls back to the straight line); request_move and _handle_move take the path; token.moved stores `cost`, which turn_usage uses. EventLog.move_token has a cost argument. New test tools/test_crowd.gd; test_turn_economy sets the rule to off for its straight-line moves. Tests: 56/56 green.
<!-- SECTION:FINAL_SUMMARY:END -->
