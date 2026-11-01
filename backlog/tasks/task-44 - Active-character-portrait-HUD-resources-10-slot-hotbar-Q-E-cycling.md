---
id: TASK-44
title: 'Active character: portrait HUD, resources, 10-slot hotbar, Q/E cycling'
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 20:45'
updated_date: '2026-11-01 21:19'
labels:
  - ui
  - tokens
  - sheet
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico, 2026-11-01:
- A user has an **active character**: a character, or a spawned entity such as a creature copy.
- In the **lower-left corner** there is a big portrait of the active one, with Health, spell points or other resources.
- **Connected to it, beside it**: a **hotbar with 10 slots**, where the character can store actions.
- **Q / E** switch round robin through all entities the user controls.
- A little **animation** when the HUD changes.

Follows TASK-43 (owners). This is the start of the character/creature sheet topic.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Open questions for Nico:
- Which entities does Q/E cycle through for the DM? Everything on the current map, only the selected tokens, or a "controlled" list?
- Does clicking or selecting a token make it the active one?
- What goes into a slot? Actions, spells, features or items dragged from the sheet or Book? Does a click (or the keys 1–0) roll it or use it?
- Where is the hotbar saved?
  - Characters: per character, in the entity, so every owner sees the same bar?
  - Creature copies: per copy, or shared with their template?
- Which resources show besides HP? Spell slots per level, hit dice, class resources (ki, rage), temp HP, AC?

Proposal (Mochi):
- Portrait = the token picture, large, in the token_style ring. HP bar plus resource pips under it.
- The hotbar is fixed to the portrait's right edge. Keys 1–0 trigger a slot.
- Animation: on Q/E the portrait slides and fades out, and the next one slides in (≈0.15 s tween). The hotbar slots flip.
- This works in the calm/minimal table view too, since it is the main player UI.

Nico, 2026-11-01 20:47:
- **Selecting or clicking a token does NOT change the active character.** You can move a fellow player's token without leaving your own character.
- **Q/E cycle through every token the user has ownership of.** For the DM, who controls everything, that is every token on the map. (Mochi's reading; to be confirmed.)

Nico, 2026-11-01 20:48: the hotbar slots stay **empty for now**. The player fills them later, never automatically. For this task: 10 empty slots in the UI; what they hold comes later.

Nico, 2026-11-01 20:49: the resources under the portrait are **HP + spell slots** for now.

Nico, 2026-11-01 21:17 (built, commit after 8037132):
- Three token states: unselected, **selected = white ring**, **active = orange ring** (the HUD's character).
- When active and selected at once: a thin white ring inside the orange one.
- **Q/E with tokens selected** cycle only through the selected tokens you control. **With nothing selected** they cycle through all of them.
- The orange ring is TokenGrid.set_active / TokenMarks.active, and CharacterHud.cycle_list() picks what Q/E go through.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 8037132. New CharacterHud (scripts/net/character_hud.gd), added by TableUI and shown in the lower left:
- **Portrait card:** the composed token picture, the name, an HP bar (cur / max, +temp) and spell slot pips per level. Slots come from the classes (5e full, half and artificer caster table, warlock pact slots) or the sheet's own `spell_slots` list. Clicking a pip spends or restores slots as a sheet.changed event (`spell_slots_used.<level>`).
- **Hotbar:** 10 empty slots, keys 1–0 labelled, attached to the right of the portrait.
- **Q/E** cycle round robin through the controlled tokens (own characters via owners; the DM controls every token on the map). The player's own character comes first and is the default.
- **Selecting a token keeps the active one.**
- **Animation:** fade, pop and turn of the portrait, and a staggered flip of the slots.
- **NetTable:** open_sheet(ref, show) plus sheet_wanted(). The HUD fetches the sheet without popping up the sheet panel; hud_ref stays open when the panel closes.

Test: test_character_hud. All 33 suites pass.

Later: filling and using the hotbar slots, and more resources.
<!-- SECTION:FINAL_SUMMARY:END -->
