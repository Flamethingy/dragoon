---
id: TASK-51
title: 'Rules P0: clean up resources, levels and inventory events'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:43'
updated_date: '2026-11-02 01:02'
labels:
  - rules
  - phase-0
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Phase 0 of rules-automation.md, a prerequisite for everything else.
- One scheme for spell slots and resources: `resource.used` / `resource.restored` (`spell_slots.N`, `ki`, feature ids). Migrate `spell_slots_used` via `sheet.changed` and the HUD pips to it.
- Levels only from `classes[].level`. `level.gained` updates the class entry in `classes`, and nothing else reads a separate `levels{}`.
- Inventory changes via `item.gained` / `item.lost` (drag onto a sheet, remove, qty) instead of replacing the whole list with `sheet.changed`.
- Player sheet edits stay allowed but show up as log lines for the DM.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Slots and resources use only resource.used/restored; old sheet.changed slot data still replays
- [x] #2 Class levels live only in classes[]; level.gained updates them
- [x] #3 Adding/removing items writes item.gained/lost
- [x] #4 Existing timelines replay unchanged; tests pass
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @Tamago
created: 2026-11-02 00:50

---

Work order from Nico (via Tamago, 2026-11-02 00:50) for Mochi: work through **all rules phases** from rules-automation.md (section 8 = Nico's decisions). Order: P0 TASK-51 → P1 53–61 → P2/P3 interleaved 62, 63, 64, 49 / 65, 66, 67, 68 → P4 69–71 → P5 72–74 only when everything else is done. Each ticket: In Progress → Done with a final summary, one commit per ticket, keep tests green. TASK-66: build it and test on at most ~5 entries, but do NOT run the full paid batch (Nico starts that). Design questions: decide in the spirit of the doc ("bookkeeping, not decisions; warn, never block") and note the choice in the ticket.

---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit b4f5f9c.

**Resources**
- Slots and resources are written only as resource.used / resource.restored (`spell_slots.N`), via `NetTable.use_resource`. The HUD pips use the difference.
- Replay maps old `sheet.changed spell_slots_used(.N)` into `resources_used`, so old timelines replay the same.
- Reading goes through `Replay.slots_used(s, level)`.

**Levels and items**
- `level.gained` updates or adds the class in `classes[]`; `levels{}` is gone.
- Items are written as item.gained / item.lost via `NetTable.change_item`. An item dropped on the sheet panel uses it.
- Spells and features keep their list sheet.changed.

**Player changes**
- A player's own changes (sheet, HP, items, resources, levels) show as hidden log lines in the DM's feed. They are also rebuilt from the event log, so they survive a restart.

**Decision:** log lines are hidden entries in the shared roll/chat feed (DM only), not a separate panel.

**Tests:** test_event_types and test_character_hud extended; 33 suites pass.
<!-- SECTION:FINAL_SUMMARY:END -->
