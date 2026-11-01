---
id: TASK-26
title: 'Monster images: PDF art and creature type icon fallback'
status: Done
assignee: []
created_date: '2026-11-01 14:22'
updated_date: '2026-11-01 14:31'
labels:
  - compendium
  - ui
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Show a picture for every monster in the compendium (list, preview, full view) and later on tokens.

Image order (see package-format.md, "Monster images"):
1. `image` field of the entry (vault image `assets/...` or PDF art `art/<id>.jpg`), path relative to the package folder. Load at runtime with `Image.load_from_file`.
2. If `image` is empty or the file is missing: the creature type icon `res://assets/creature_types/<type lowercase>.svg` (white glyph, tint it, e.g. with the type colour or the theme's text colour). Types without an icon (e.g. Abomination) use `unknown.svg`.

The icons are game-icons.net, CC BY 3.0: add an "Credits" entry somewhere in the app (about/credits screen or the package view) that shows `assets/creature_types/CREDITS.md`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Monsters with an image show it in list, preview and full view
- [x] #2 Monsters without an image show their type icon, unknown types the unknown icon
- [x] #3 Missing image files fall back to the icon without errors
- [x] #4 The CC BY credits for the icons are visible in the app
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Cards, the quick card and the full view show the monster's image. ImageCache.decode loads by content (JPEGs named .png work; broken or missing files fall back quietly). Without a picture they show the creature type icon (matched inside the type text, unknown.svg otherwise), tinted in the card colour. A Credits button on the compendium cover shows assets/creature_types/CREDITS.md (CC BY 3.0). Test: tools/test_monster_art.gd. Commit: 1d0cf9a. Note: assets/creature_types/ itself is not committed yet (it is the importer side's); without it the cards fall back to the initial.
<!-- SECTION:FINAL_SUMMARY:END -->
