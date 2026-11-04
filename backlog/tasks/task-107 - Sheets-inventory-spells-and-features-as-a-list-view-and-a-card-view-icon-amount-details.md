---
id: TASK-107
title: >-
  Sheets: inventory, spells and features as a list view and a card view (icon,
  amount, details)
status: Done
assignee: []
created_date: '2026-11-04 21:42'
updated_date: '2026-11-04 21:52'
labels:
  - sheets
  - hud
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico (2026-11-04): "Let's get the skills and items working! First freshen up the inventory and skill list in the character sheets: two versions, one with a card view and one with a list view that also shows the icon, the amount and so on."

I read "skill list" as the spells and features, the things a character uses. The D&D skill checks are already roll buttons and stay as they are.

Each of the Inventory, Spells and Features pieces gets two views:
- **List:** a row per entry with:
  - an icon (item type / spell level / feature);
  - the name and a detail line (damage, AC, type, school, action type ...);
  - marks (equipped, attuned, concentration, ritual);
  - the amount (qty, qty/max, charges, free slots, uses left).
- **Cards:** a grid of cards with the icon, the name and an amount badge.

Both views scroll. A click uses the entry like a quick button (cast / use). A toggle in the piece's header switches the view per client; the layout editor offers both as variants.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Inventory, Spells and Features each have a list view (icon, name, details, marks, amount) and a card view (icon, name, amount badge)
- [x] #2 Amounts: item qty / max and charges, spell slots of the level, feature uses left
- [x] #3 A header toggle switches the view (kept per client); the layout editor offers both variants
- [x] #4 Clicking an item uses it, a spell casts it (as the quick buttons do); long lists scroll
- [x] #5 Tests pass
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
New `scripts/hud/sheet_lists.gd` (SheetLists) builds the Inventory, Spells and Features pieces. HudWidgets uses it, and those kinds get the variants "list" and "cards".

- **List view:** a row per entry with:
  - an icon (the entry's picture if it has one, else a coloured plate with a sprite by item type: sword, shield, armor, potion, ring, boots, helmet, gem, coin, chest; the spell level; or the initial);
  - the name and a detail line (damage + bonus + type, AC, item type, rarity, charges; level, school, casting time; class and level);
  - marks: E equipped, A attuned / a needs attunement, C concentration, R ritual;
  - the amount (qty/max or ×qty, free slots of the spell's level, uses left).
  - Spells are grouped by level, features by list (Features, Traits, Actions …).
  - Spent entries are faded.
- **Card view:** a grid with a big icon, the name, an amount badge and the marks.
- **Toggle:** ☰ / ▦ in the header. It is saved per kind in `user://sheet_views.cfg` (per client); otherwise the layout's variant is used.
- **Clicking** an item or spell calls `hud.use_quick` (use / cast). Features show a tooltip only (making them usable comes next).
- **Host:** `NetTable._refs` now sends more detail: school, concentration, casting time, image; item type, rarity, weight, image; the feature lists with attack/save.
- **Tests:** new `tools/test_sheet_lists.gd`. Fixed the flaky "walks along the bottom" check in test_table_bunny: it sometimes hopped in place instead. The character_hud, sheets, detached_pages, class_features, app and bunny suites pass.
<!-- SECTION:FINAL_SUMMARY:END -->
