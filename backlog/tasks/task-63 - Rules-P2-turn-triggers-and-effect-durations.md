---
id: TASK-63
title: 'Rules P2: turn triggers and effect durations'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
updated_date: '2026-11-02 02:10'
labels:
  - rules
  - phase-2
  - combat
dependencies:
  - TASK-56
  - TASK-58
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- Effects and conditions get durations: rounds, "until start/end of X's next turn", minutes/hours (in-world clock), concentration-linked.
- Turn engine at start/end of each turn:
  - recharge rolls (Recharge 5–6) for creature features
  - "save ends" prompts (save at end of turn)
  - ongoing damage, regeneration (with "unless fire/acid" as a reminder)
  - legendary action counter reset, reaction reset
  - expiring effects
- Expired effects are removed with a log line (undoable), per the table setting.
- Legendary actions/resistances as counters on the creature.
- Lair actions: a reminder at initiative 20.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Durations by round/turn/clock tracked and expiring with a log line
- [x] #2 Recharge rolls at turn start
- [x] #3 Save-ends prompts at the right moment
- [x] #4 Legendary action/resistance counters reset correctly
- [x] #5 Lair reminder at initiative 20
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices (Mochi):
- A duration is {rounds, ends: turn_end | (turn start), of: whose turns count, save_ends: {ability, dc}}; replay adds since/day/time. A save effect's "for 1 minute" counts the actor's turns ("its next turn" counts the target's); with no source it counts the holder's own turns.
- Expiry follows the "durations" automation: Auto removes the condition with an undoable log line, Assist only reminds the DM, Off does nothing.
- Save ends: the DM's creatures roll right away; players get the usual save prompt (the TASK-55 flow). A success removes the condition.
- Recharge: a d6 at the start of the creature's turn for features it used (action.used) that have not come back yet; a success logs feature.recharged; a DM line either way.
- Legendary actions: the count (intro text, else 3) comes back at the start of its turn; "Costs N Actions" is counted. Legendary Resistance (N/Day) is counted since the last long rest (event rest.taken {kind: long}, which comes in TASK-64). Both are LA/LR buttons on the DM's tracker rows; spent recharges are listed there too.
- Regeneration and ongoing damage are reminders only (DM line with the "unless acid/fire" note). Nothing is applied by itself.
- Lair: a DM reminder at the initiative-20 crossing or at the round wrap, for creatures with lair_actions or a "Lair Actions" feature.
- Clock: NetTable.advance_clock(minutes) (time.advanced). Out of combat it ends minute durations (10 rounds = 1 min). No UI button yet.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Turn engine in next_turn (commit b45f76f): durations, save-ends, recharge, legendary counters, regeneration and lair reminders, plus a clock helper. Test tools/test_turn_engine.gd; suite 43/43 green.
<!-- SECTION:FINAL_SUMMARY:END -->
