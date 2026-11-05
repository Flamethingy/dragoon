---
id: TASK-96
title: 'Table Bunny 2: VTT tool registry with per-player permission checks'
status: Done
assignee: []
created_date: '2026-11-04 14:30'
updated_date: '2026-11-04 14:57'
labels:
  - ai
  - bunny
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**On hold until Nico approves the design: [[doc-3]] Table Bunny design.**

`BunnyTools`, defined once in one place: name, description and JSON schema for each tool, plus `call(tool, args, peer)`.

The tools:
- `rules_lookup`, `compendium_search` / `compendium_get` (revealed entries only, no drafts);
- `sheet_read`;
- `add_to_sheet` (the TASK-94 path);
- `roll`;
- `combat_state` (through `Reveal`);
- `note_write`.

Rights:
- every call runs with the rights of `peer` (`Reveal`, `_editable`, `is_dm`). If something isn't allowed, the tool returns an error and the model never decides about rights;
- changes only go through the normal event log;
- no file, shell or network access.

It is also the base for the MCP server (TASK-99).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each tool has a schema and checks the asking peer's rights
- [x] #2 A player can't read hidden info or change another player's character through any tool
- [x] #3 Changes go through the event log (undo works)
- [x] #4 Headless test per tool, incl. denied cases
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit dd56372.

**`BunnyTools`** (`scripts/bunny/bunny_tools.gd`) is the one tool list for the bunny (TASK-95) and the MCP server (TASK-99).
- `TOOLS` has a name, description and `input_schema` per tool, in Messages API format; `schemas()` and `names()` return them.
- `run(table, tool, args, sender)` runs on the host only, as the player of peer `sender` (1 = DM). It returns `{result}` or `{error}`.

**The tools:**
- `rules_lookup`: conditions (Rules, for the world's edition) plus "rules" entries.
- `compendium_search` / `compendium_get`: no drafts for players; timeline and world entries through `entry_for` (Reveal and grants), package entries through `Reveal.filter_entry`. Hidden entries look like missing ones.
- `sheet_read`: only `may_see_sheet` (own character; DM: all), without internal `_` keys.
- `add_to_sheet`: the TASK-94 path `_handle_add_entry`; items, spells and features only.
- `roll`: `_handle_roll` with the player's rights.
- `combat_state`: round and order; HP only for creatures the asker may see the sheet of.
- `note_write`: `_handle_note` in the player's name.

**Rights:** every change goes through the same host handlers as the buttons, so it's an event in the player's name and can be undone. No file, shell or network access. Unknown tools are refused.

**Test:** `tools/test_bunny_tools.gd`, per tool, with denied cases.
- Bob can't see a draft place or Mira's DM-only passage, and can't read, change or roll for Mira.
- Bob adds a potion to Borin: one event in his name, and undo removes it.
- Refused calls make no events.
- Combat HP: Bob sees only Borin's; the DM sees all.
- Notes are in his name.
- Only runs on the host.
<!-- SECTION:FINAL_SUMMARY:END -->
