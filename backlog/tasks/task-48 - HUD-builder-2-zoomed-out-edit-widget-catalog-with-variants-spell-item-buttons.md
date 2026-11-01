---
id: TASK-48
title: >-
  HUD builder 2: zoomed-out edit, widget catalog with variants, spell/item
  buttons
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 23:37'
updated_date: '2026-11-01 23:56'
labels:
  - ui
  - sheet
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico, 2026-11-01 23:37:
- **F2 mode "zooms out":** the screen is shown smaller, so the builder UI fits comfortably around it.
- **A "Sims-like" building system, or like the Android widgets menu:** you see the elements and can find **different variants of the same function**. E.g. the portrait is the token right now, but it could also be the **full portrait** picture.
- **Skills and items as quick buttons**, square or round, on the screen.
  - If the entity has an amount (e.g. Torches 0/10), the amount shows on the button.
  - Clicking the button casts the spell or uses the item.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Clicking a spell, item or check button posts it in the chat with its rolls; nothing is spent
- [x] #2 F2 edits the sheet pages if one is open, otherwise the HUD; F3 does not open an editor
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Mochi's plan:
- **Edit mode:**
  - The screen preview is scaled to about 70% at the top centre.
  - Below it is a **catalog tray** (Sims build bar), with category tabs:
    - Character: portrait variants, health, spell slots, info
    - Checks: abilities, saves, skills, a single check
    - Spells: one button per spell of the character
    - Items: one button per inventory item
    - App: Compendium, Book, Leave, chat
  - Each entry is a **live preview card**. Variants sit side by side: Portrait (token, round) / Portrait (full picture) / Portrait (small with name); Health (bar / number / hearts?); buttons (square / round).
  - Drag a card onto the screen preview to place it.
- **Quick buttons:** a piece `{w: "spell" | "item" | "check", ref, shape: square | round}` showing the picture or icon, name on hover, and the amount badge (qty, or uses/max).

Open questions:
- What does casting a spell do?
- What does using an item do?
- Where does "max" come from (0/10)?

Nico, 2026-11-01:
- For now a click on a spell/item/check quick button only posts it in the chat (with its rolls); nothing is spent. The real usage engine (does it need a slot, is one free, spend it, then roll and apply effects) comes later as its own task.
- Both edit modes go on F2: with a sheet page open, F2 edits the pages; otherwise it edits the HUD. F3 is no longer an editor key.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 1120a0e.
- **F2:** edits the open sheet page, otherwise the HUD.
- **Editor:** the screen is shown at about 68% (the map shrunk behind it), with a catalog tray below.
  - Tabs: Character / Checks / Spells / Items / App.
  - Live preview cards, with variants side by side.
  - Click a card or drag it onto the screen; double-click a piece to switch its variant.
- **Quick buttons:** spell, item or check, square or round, each with an amount badge.
  - A check rolls.
  - A spell or item is posted in the chat with its rolls (HudActions).
  - Nothing is spent yet (TASK-49).
- **Tests:** test_character_hud extended, screenshot_hud updated; 33 suites pass.
<!-- SECTION:FINAL_SUMMARY:END -->
