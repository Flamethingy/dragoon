---
id: TASK-46
title: Chat box on the right; HUD check panels instead of the hotbar
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 22:03'
updated_date: '2026-11-01 22:10'
labels:
  - ui
  - sheet
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico, 2026-11-01 22:03 (start of the character sheet and HUD topic):
- **Chat box on the right:** for now only the chat box and a field where players can write.
- **Remove the hotbar** again. Instead, add panels next to the portrait with the **ability, save and skill checks**.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 3a7294a.
- **ChatBox** (scripts/net/chat_box.gd) on the right of the calm table:
  - Messages are NetTable.say → `chat.message` events, shown in one feed with the session's rolls.
  - Enter sends and gives the keys back to the map. `/r <formula or check>` rolls for the active character.
  - Outside the calm table, the Session panel shows the chat entries too.
- **HUD:** the hotbar is removed. Next to the portrait are three panels:
  - Abilities: score and modifier.
  - Saves.
  - Skills: two columns, proficient ones in wine red.
  - A click rolls the check for the active character into the chat. Shift = advantage, Ctrl = disadvantage.
- Tested in test_character_hud. All 33 suites pass.
<!-- SECTION:FINAL_SUMMARY:END -->
