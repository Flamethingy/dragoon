---
id: TASK-43
title: 'Characters and Creatures: merge PCs+NPCs, rename monsters, migrate data'
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 19:14'
updated_date: '2026-11-01 20:13'
labels:
  - data
  - tokens
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico, 2026-11-01: combine players and NPCs. The only difference is that NPCs may have manual traits instead of a class. Open questions to settle with Nico:
- the kind name (characters?)
- how player ownership is marked
- migrating the existing pcs/ and npcs/ refs in worlds, timelines and event logs
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Nico, 2026-11-01: the merged kind is called **Characters** (characters/<id>).

Nico, 2026-11-01, on ownership:
- Characters (and items) have a list of **owners** (player ids).
- The DM always controls every token and basically everything.
- The DM can assign owners.
- When a player creates an item or a character, they are added as an owner automatically.

Nico, 2026-11-01: convert everything automatically (worlds, timelines, events).

Plan (Mochi):
- **New kind `characters`.** Schema = PC fields + NPC fields:
  - race, classes (optional), background, alignment, role, attitude, location, factions, inventory, spells, features
  - `traits` for NPCs without a class
  - `owners: [player ids]` replaces `player`
- **Migration on start** (like Worlds.migrate_data), for worlds, timelines and homebrew packages:
  - pcs.json + npcs.json are merged into characters.json; old files are kept as *.json.bak
  - `"pcs/` and `"npcs/` refs become `"characters/` in all json/jsonl files (entries, maps, timeline.json, events) and in `[[...]]` links
  - id clashes between a PC and an NPC: the NPC gets a "-npc" suffix
- **Code:**
  - CREATURES = characters + monsters
  - Timeline.owners() becomes ref -> [players]; pc_choices = characters (a player picks one and is added as an owner)
  - the DM controls everything; players move and edit what they own
  - a player who creates an entry is added to its owners
  - the DM edits owners in the entry form (a player picker)

Nico, 2026-11-01, Characters vs Creatures:
- **Monsters become "Creatures"** (bandits and animals too).
  - Done for the UI in a397ab8 (Compendium.kind_label).
  - The data kind `monsters` -> `creatures` is renamed in this task's migration: core packages too, refs like `monsters/goblin` -> `creatures/goblin`, features' used_by, events.
- **Creatures** dropped on the map are copies: 5 goblins = 5 entities with 5 HP bars. Already the case: token_entity makes numbered copies.
- **Characters** are referenced: every token of a character is that one entity, with one health pool saved with it (the Book shows its current state).
  - Already true for world NPCs and PCs: refs, HP as events on the one ref.
  - Still to do: core NPCs dropped twice, and showing the current HP in the Book.
- The sheet popping up on a token click was removed (a397ab8). The character/creature sheet is the next topic after this.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 13303e0. PCs + NPCs merged into `characters` (with `owners` list of player ids; DM controls everything), `monsters` renamed to `creatures` (UI label "Creatures"). New KindMigration (scripts/data/kind_migration.gd) converts packages, worlds and timelines lazily on first open (EntryStore.open, PackageDB, Timeline): kind files merged (PC `player` -> `owners`, clashing NPC ids get "-npc"), refs in all .json/.jsonl rewritten (entries, events, notes, package counts), *.bak backups kept, `.kinds2` marker. NetTable owners are lists (owns()/owner_of()). Example world migrated. New test_kind_migration; all 32 suites pass. Open: auto-adding a player as owner when they create an entry (players can't create entries yet); owners are edited as a plain list field for now.
<!-- SECTION:FINAL_SUMMARY:END -->
