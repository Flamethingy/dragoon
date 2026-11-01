---
id: TASK-6
title: 'Unified index: campaign, world and core entries'
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-01 11:17'
updated_date: '2026-11-01 13:55'
labels:
  - mvp
  - data
dependencies:
  - TASK-20
documentation:
  - data-layout
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Originally "parse markdown entities with a startup cache". With JSON everywhere ([[data-layout]]) and the compendium's package_db already loading core packages, this becomes: one index over campaign → world → core, so lookups and wikilinks resolve in that order (a campaign copy of Mira wins over the world original). Cache only if loading gets slow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Campaign, world and core entries are in one index with layer priority campaign > world > core
- [x] #2 Wikilinks [[Name]] resolve with that priority
- [x] #3 Loading time measured with all 34 packages + example campaign; cache added only if > 2 s
- [x] #4 Campaign entries appear in the compendium and open in the entry editor (TASK-21 hookup): EntryStore for the campaign folder, campaign names in [[ suggestions, the table's EventLog passed to Compendium.event_log so session edits become events
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PackageDB.campaign_dir loads a campaign's kind files next to the packages; every entry gets `_layer` (campaign/world/core). resolve() ranks campaign > the campaign's world > other worlds > core, then kind and package. resolve_ref handles kind/id, world:kind/id and core:pkg/kind/id. Load time: 16,484 entries from 34 packages + the example campaign in ~0.4 s, so no cache. Compendium: a campaign picker on the cover (remembered with the tabs). It opens the campaign's events.jsonl, so edits during a session become events. The campaign is a writable store for New... and "edit a copy". At the table the DM has a "Compendium" button: the book opens over the table with the table's campaign and EventLog. Bug fixed along the way: the speed field dropped zero values, which produced a spurious sheet.changed. Test: tools/test_unified_index.gd. Commit e73a911.
<!-- SECTION:FINAL_SUMMARY:END -->
