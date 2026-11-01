---
id: TASK-51
title: 'Rules P0: clean up resources, levels and inventory events'
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:43'
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
- [ ] #1 Slots and resources use only resource.used/restored; old sheet.changed slot data still replays
- [ ] #2 Class levels live only in classes[]; level.gained updates them
- [ ] #3 Adding/removing items writes item.gained/lost
- [ ] #4 Existing timelines replay unchanged; tests pass
<!-- AC:END -->
