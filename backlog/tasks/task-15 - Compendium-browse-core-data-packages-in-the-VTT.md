---
id: TASK-15
title: 'Compendium: browse core data packages in the VTT'
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-01 11:30'
updated_date: '2026-11-01 12:08'
labels:
  - mvp
  - data
  - ui
dependencies: []
documentation:
  - package-format
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The VTT is the viewer for core data (see package-format). Load all packages from `data/packages` at runtime and show a compendium: list per kind with search and filters (source, CR/level, type, school), and a detail view that renders the Markdown text fields (Markdown to BBCode in a RichTextLabel) plus the stat block layout for monsters and spells.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All packages in data/packages load at startup without freezing the UI (4000+ entries)
- [x] #2 List view per kind with text search and filters (package, CR or spell level, type/school)
- [x] #3 Monster detail shows the stat block, features and Markdown description
- [x] #4 Spell detail shows level, components, range, duration and Markdown description
- [x] #5 Wikilinks in text open the linked entry if it exists
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
PackageDB loads data/packages on a WorkerThreadPool task (index by kind + by lowercased name for wikilinks). Markdown->BBCode converter (from Tamago's markdown.gd) + [[wikilinks]] as wiki: meta links. StatBlock formats monsters, spells and a generic layout for other kinds. Compendium scene: kinds list | filters + sortable Tree | detail (image + RichTextLabel, back history). Headless test formats every entry.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-01 12:10 (Mochi): Redesigned the compendium as a card collection book with Nico's sprite sheet `assets/ui_sprites.png`.
- `UISkin` (`scripts/ui/ui_skin.gd`) holds the sprite regions, 9-slices, palette and one shared Theme.
- Bookmark tabs per kind sit on the wine cover. The middle is a binder page: a grid of `EntryCard`s showing the picture, a hex badge (CR tier colour, spell level, rarity or hit die), name and subtitle. The grid pages with arrows or PgUp/PgDn and resizes to the window.
- The open card shows a title plate, a big framed picture, stat chips with icons, ability hexes, the source, and the full StatBlock text folded under "Full text".
- Entries without art get a fallback (`CardArt`): a plate coloured by type or school, with a ring and the initial.
- Images load on worker threads (`ImageCache`). Text colours are switched to ink on paper.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The compendium scene is `scenes/compendium/compendium.tscn`.

- **Loading:** `PackageDB` loads every package in `data/packages` on a WorkerThreadPool task: 4309 entries from 34 packages in about 0.25 s. A progress bar shows while it loads and the UI stays responsive. It builds an index by kind and by lower-case name.
- **List:** kinds are on the left with their counts. The middle list searches names (debounced), with a "Search text too" option for descriptions and features. Filters: package, CR (monsters) or level (spells), and type/school/item type. Columns sort by name, CR/level, type or package.
- **Detail:** `StatBlock` gives monsters a full stat block (AC, HP, speed, ability table with modifiers, saves, skills, resistances, senses, languages, CR with XP, then traits, actions, bonus actions, reactions, legendary actions and the description). Spells get level and school, ritual, casting time, range, components with material, duration with concentration, classes and the description. Other kinds get a field table plus their Markdown sections. The entry's image shows above.
- **Markdown and links:** `scripts/ui/markdown.gd` is ported from Tamago. It now turns `[[Target#Section|Label]]` (also with an escaped pipe in tables) into links. Clicking one opens the entry, preferring the same package and then the kind priority. Back or Alt+Left returns, and Ctrl+F focuses the search.
- **Test:** `tools/test_compendium.gd` formats all 4309 entries without errors. 2434 of 2888 wikilinks resolve; the others point to PDFs or pages that don't exist.
- **Not done:** scrolling to the `#Section` inside the opened page.
<!-- SECTION:FINAL_SUMMARY:END -->
