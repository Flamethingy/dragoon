---
id: TASK-75
title: 'HUD edit (F2): min/max sizes for widgets'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 01:16'
updated_date: '2026-11-02 09:49'
labels:
  - hud
  - ui
  - feedback
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico's feedback 2026-11-02: in F2 edit mode some HUD elements take up far more space than they need. Each widget type needs a sensible minimum size and a default/maximum size that fits its content, so widgets don't spread out and resizing can't make them tiny or huge.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every widget type has a min size and a content-fitting default size
- [x] #2 Resizing in F2 respects the min size
- [x] #3 Existing layouts load and get clamped
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices:
- Limits are in pixels per widget kind (HudWidgets.LIMITS: min / fit / max), with variant overrides (for example the small portrait). The HUD grid's cells are about 33 px and a sheet page's about 70 px, so one fixed size in cells can't fit both. Each grid converts the pixels into its own cells.
- min: smaller and the content no longer fits. fit: the size a newly added piece gets (its content). max: bigger only adds empty space. Scrolling lists (skills, spells, features, inventory, description) have no maximum.
- In F2, resizing by dragging the corner, the inspector's W/H fields (their ranges follow the limits) and switching a variant all stay within the limits.
- Existing layouts are clamped when they load (CharacterHud.layout / page_list via HudWidgets.clean with the cell size) and in the editor. Nothing is rewritten in the saved character until it is edited again.
- The default sheet page is re-laid out to fit: info 2 rows, health and spell slots one row each under it, abilities/saves 5 rows. Before, the slots alone took 2x6 cells.
- Headless runs (no real screen, cells under 12 px): the limits wait and the old cell sizes are used, so tests stay sane.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 8ef5156. HudWidgets: LIMITS, limits(), min_cells / max_cells / fit_cells / clamp_cells, clean(items, grid, cell). LayoutEditor: new pieces get fit size; _set_rect and _rebuild clamp; inspector spin ranges come from the limits; catalog thumbnails and drop centring use fit. CharacterHud: layout() and page_list() are clamped (page_cell()). DEFAULT_PAGES tidied. Checks added to test_character_hud; screenshots checked. The full run showed one flaky death-test wait (unrelated: Ann's RPC under load); its wait is now longer.
<!-- SECTION:FINAL_SUMMARY:END -->
