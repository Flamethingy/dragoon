---
id: TASK-32
title: Worlds with timelines instead of campaigns
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 15:52'
updated_date: '2026-11-01 16:11'
labels:
  - mvp
  - data
  - decision
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico's decision, spec in timelines.md. A world (package) has timelines: each one is a history of play as events on top of the world, git-like. A start timeline is created with the world, and campaigns are forks of it. Entries created in a timeline (new items, NPCs, PCs) are `entity.created` events, and they can be promoted into the world. "Send into campaign" goes away; refs resolve timeline → world → core.

Includes migrating the code (EntryStore, unified index, net table, sheets, notes, event log/replay) and the example red-fang campaign into a timeline of westmarch.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 data/worlds/<world>/timelines/<id>/ with timeline.json, events.jsonl, notes.json, encounters.json as in timelines.md
- [x] #2 Creating a world creates its start timeline; a timeline can fork from another at an event and shares events up to there
- [x] #3 Entries created during a timeline are entity.created events, visible only in that timeline and its forks; Promote moves one into the world
- [x] #4 World files are never changed by play; state = world + timeline events
- [x] #5 red-fang is migrated to a westmarch timeline; all test suites pass
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit d017955.

**New code**
- `scripts/world/timeline.gd` (Timeline): replaces Campaign. Entries are the world's entries plus the timeline's own, built from entity.created / entity.edited / entity.deleted / entity.promoted events. Also handles players and colours in timeline.json, the map/token/entry views, add_entry, edit_entry, delete_entry, promote, fork, create and list.
- `scripts/world/worlds.gd` (Worlds): create (also makes the Prologue), list, install_example, migrate_campaign and migrate_data. migrate_data runs at app start and through `tools/migrate_data.gd`.

**Changes to existing code**
- **EventLog:** inherited parent events up to fork_at. Own ids continue after them. Several EventLog objects on one file stay in sync (it reloads before appending if the file grew).
- **EntryStore:** a new timeline layer. Saving appends entity events; in a session, sheet fields become sheet.changed events as before. send and send_world are removed.
- **PackageDB / PackageManager:** load and list worlds from data/worlds next to data/packages (a new world from an import goes there too). timeline_dir replaces campaign_dir, and ranking is timeline > world > core.
- **NetTable / TableUI:** use a timeline folder (`--timeline=`). The default is the example data/worlds/westmarch/timelines/red-fang. Tokens placed by events now show even if they are not in the map's starting layout.
- **Compendium:** a timeline picker. "Send to campaign" became "Promote to world" (only for timeline entries). Accounts are gathered from every timeline.

**Example and migration**
- examples/worlds/westmarch now has the Prologue and the red-fang timeline (forked at 0).
- Its maps forest-road and old-mill, and the place old-mill, went into the world. Their token layout became token.placed events.
- PCs, the goblin chief, the dire wolf, the amulet and the features became entity.created events.
- The copies of Mira, Thornwick and the other world entries became plain refs.

**Docs:** doc-1 documents the entity.* events and one log per timeline.

**Tests:** the new `tools/test_timelines.gd` covers the start timeline, forks, created entries visible only in their timeline, Promote, an unchanged world, and the migration of an old data folder. test_send was removed and the other suites were converted. All 24 suites pass.
<!-- SECTION:FINAL_SUMMARY:END -->
