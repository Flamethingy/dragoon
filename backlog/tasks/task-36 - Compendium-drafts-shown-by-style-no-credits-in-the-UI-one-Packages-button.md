---
id: TASK-36
title: 'Compendium: drafts shown by style, no credits in the UI, one Packages button'
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 15:52'
updated_date: '2026-11-01 16:39'
labels:
  - compendium
  - ui
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Three small fixes from Nico:
1. **Drafts:** remove the visible draft yes/no field from the sheets and editor. Instead, a draft's title is *italic* and its text slightly grey (the full view, cards and lists). Save as draft / Publish / Back to draft buttons stay.
2. **Credits:** remove the credits from the compendium UI. Credits stay as a file only, e.g. `CREDITS.md` in the project root, which can list `assets/creature_types/CREDITS.md`.
3. **Packages:** the menu has "Packages" twice. Keep the **lower** position. Clicking it opens the package card overview (the one the top button opens now). Remove the top button and the popup of the lower one, and move all popup functions into the overview: import, export, import from link, delete, unlock and so on.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No draft field in sheets/editor; drafts have an italic title and greyed text
- [x] #2 No credits in the UI; credits file in the project
- [x] #3 Only one Packages entry (lower position) opening the card overview
- [x] #4 All former popup functions are available in the overview
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Drafts: the "Draft: yes/no" line in stat blocks (generic kinds) is gone (draft, edited, copy_of, copy_number and _ keys hidden), as are the card's Draft tag and the "Draft ·" subtitle. A draft's title is italic and grey (UISkin.mark_draft / italic_font) in the full view, on cards and in stat block titles, and its text is grey. Save as draft, Publish and Back to draft stay. Credits: the Credits button and dialog are removed; CREDITS.md in the root points to assets/creature_types/CREDITS.md. Packages: the top "Packages" bookmark and the PackagesPanel popup are removed (packages_panel.gd deleted). The lower Packages entry (a bookmark-style toggle with its count) opens the card overview. Import... and Import from link... sit above the cards; a package's view has Shown in the book (on/off), Export..., Unlock for editing (read-only source packages) and Remove.... Tests updated (drafts, package_cards, import_ui, monster_art); screenshot checked. Commit c8f6e81.
<!-- SECTION:FINAL_SUMMARY:END -->
