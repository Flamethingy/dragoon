---
id: TASK-22
title: 'Compendium: document tabs with a full view per entry'
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-01 13:15'
updated_date: '2026-11-01 13:30'
labels:
  - mvp
  - ui
  - data
dependencies: []
documentation:
  - package-format
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico likes the compendium's look (card binder + detail column), but the right-hand detail column (DETAIL_WIDTH 430, full text folded under "Full text") is too small to really read an entry, and opening another card replaces it.

Add a **tab bar above the search/filter row** (like browser tabs):
- The first tab is always **Browse**: today's binder view (bookmark kinds, search, filters, pages, quick detail card on the right). It can't be closed.
- Opening an entry in full (double-click a card, "Open" button on the detail card, middle-click, or Ctrl+click a wikilink) opens it in **its own tab** with a **full view** that uses the whole width: picture, stat block, all fields and the complete Markdown text, laid out properly (e.g. two columns for monsters: stats/features left, description/lore right). Features of monsters are listed with their full text; feature ids and wikilinks are clickable and open in a new tab.
- Tabs show icon + name, have a close button (and middle-click to close), can be reordered by dragging, and remember their scroll position. If an entry is already open, its tab is focused instead of opening a duplicate.
- Shortcuts: Ctrl+W closes the tab, Ctrl+Tab / Ctrl+Shift+Tab switch tabs. Open tabs are restored on the next start.
- Each full-view tab gets an **Edit** button. For now it can be disabled with the tooltip "Coming with the entity editor (TASK-21)". TASK-21 plugs its editor into this tab, so the full view and the edit view are the same place.

Works for every kind (monsters, spells, items, features, classes ...) and for world/campaign entries once those load.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A tab bar sits above the search/filter row; the first tab 'Browse' holds the current binder view and cannot be closed
- [x] #2 Double-click, the 'Open' button, middle-click on a card and Ctrl+click on a wikilink/feature open the entry in its own full-view tab; an already open entry is focused instead of duplicated
- [x] #3 The full view uses the whole width and shows all fields and the full Markdown text for every kind (monster layout: stats/features + description side by side)
- [x] #4 Tabs can be closed (button, middle-click, Ctrl+W), switched (Ctrl+Tab), reordered by drag, keep their scroll position, and are restored after a restart
- [x] #5 Each full-view tab has an Edit button (disabled until TASK-21, with a tooltip)
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
"Browse" is a fixed button that can't be closed, left of a TabBar. Double-click or middle-click on a card, "Open" on the quick card, or Ctrl+click on a link opens a full-view tab (EntryView, scripts/compendium/entry_view.gd). Each tab has a title plate with a disabled Edit button (tooltip points to TASK-21). Monsters get two columns (stat block and features left; picture, chips and description right); other kinds show picture and chips left and the full text right. Links in full views open new tabs, and an entry that is already open is focused instead of duplicated. Tabs close with x, middle-click or Ctrl+W; Ctrl+Tab and Ctrl+Shift+Tab cycle; drag reorders. Scroll positions are kept, and tabs, the shown tab and scroll come back after a restart (user://compendium_tabs.json). Test: tools/test_compendium_tabs.gd. Screenshots: tools/screenshot_compendium.gd. Commit d3b2453.
<!-- SECTION:FINAL_SUMMARY:END -->
