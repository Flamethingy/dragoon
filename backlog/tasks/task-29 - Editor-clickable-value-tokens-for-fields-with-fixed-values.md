---
id: TASK-29
title: 'Editor: clickable value tokens for fields with fixed values'
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 14:43'
updated_date: '2026-11-01 14:57'
labels:
  - editor
  - ui
dependencies:
  - TASK-21
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From Nico: fields whose values repeat (tags, rarity, type, race, subrace ...) should be edited by clicking tokens (chips) instead of typing, with a "+" token to add a new value right in the sheet. Builds on the entity editor (TASK-21).

**How it works**
- Single choice fields: one token selected, click another to switch (e.g. size, type, rarity, school).
- Multi choice fields (lists): click to toggle any number of tokens (e.g. tags, classes, condition immunities).
- The token list = every value this field already has in the loaded packages/campaign (core + world + campaign), most used first. Long lists show the top ~12 plus a search box.
- "+" token: type a new value (with autocomplete against the known ones, so "very rare" doesn't become a second "Very Rare"); it is saved in the entry and then shows up as a token everywhere.
- Ref fields (race, subrace parent, subclass class, factions, location) use the same tokens but point at entries (`races/half-elf`), and clicking with Ctrl opens the entry.

**Fields (from the current data)**
| Kind | Single choice | Multi choice |
| --- | --- | --- |
| all | | tags |
| monsters | size (8), type (15), subtype, alignment, group | condition_immunities, immunities, resistances, vulnerabilities, languages, environments |
| items | rarity (7) | type (25) |
| spells | school (9), subschool, casting_time, duration | classes (20) |
| classes | spellcast_ability | saving_throws, prof_armor, prof_weapon, prof_skills |
| subclasses / subraces | class / parent (ref) | |
| features | uses (Recharge 5-6, 1/Day ...) | |
| tables | dice | |
| pcs / npcs | race (ref), alignment, attitude | factions (ref) |

Fixed base lists exist even with no data: sizes, the six abilities, damage types, conditions, spell schools, rarities, alignments.

Fields with numbers inside (senses "Darkvision 18 m", armor, speed) stay text for now. casting_time and duration can be tokens with free text allowed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Single and multi choice fields in the editor show their known values as tokens; clicking selects or toggles
- [x] #2 A + token adds a new value with autocomplete, and it appears as a token afterwards
- [x] #3 Token lists come from all loaded entries, most used first, with search for long lists
- [x] #4 Ref fields store refs and can open the referenced entry
- [x] #5 Base lists (sizes, abilities, damage types, conditions, schools, rarities, alignments) are always available
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit be77cb1.
- `Schema.TOKENS` turns repeating fields into `token` / `tokens`: tags, size, type, alignment, damage/condition lists, languages, environments, rarity, item type, school, casting time, duration, spell classes, class abilities and proficiencies, uses, dice, race, factions, location, subclass class and subrace parent. Guessed fields of other kinds are covered too.
- Base lists are always offered.
- `PackageDB.field_values` returns the known values, most used first, with spellings merged and a cache.
- TokenField:
  - Click to switch, toggle or clear.
  - Shows the top 12 plus "N more..." and a search for long lists.
  - "+" / Enter adds a new value, but picks an existing one written in another spelling.
  - Ref fields store `kind/id` (pc race, factions, location). Npc race, subclass class and subrace parent are stored as names, the way the data has them.
  - Ctrl+click opens the entry.
- Also used in the import review editor.
- Test: `tools/test_tokens.gd`.
<!-- SECTION:FINAL_SUMMARY:END -->
