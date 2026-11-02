---
id: TASK-77
title: 'F2: remove the hardcoded "Compendium / Book / Leave" bar'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 01:16'
updated_date: '2026-11-02 08:43'
labels:
  - hud
  - ui
  - feedback
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico's feedback 2026-11-02: in F2 edit mode the hardcoded "Compendium, Book and Leave" buttons get in the way and aren't needed. Remove them (these actions stay reachable through the menu, shortcuts or HUD widgets).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The hardcoded bar is gone in F2
- [x] #2 Compendium, Book and Leave are still reachable another way
- [x] #3 Tests pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Cause: the app's top-right bar (ViewBar) steps aside only while the HUD shows the app buttons as pieces. F2 hides the HUD while the editor is open, so the hardcoded bar popped up over the editor.

Design choices:
- While the F2 editor is open, the bar is never shown.
- Outside F2 it stays only as a fallback: when the HUD doesn't carry the Compendium / Book / Leave pieces (no active character, or the user removed them from their layout). Without it there would be no way left to leave the table. With the default HUD it never shows, because the default HUD already has Combat, Rules, Compendium, Book and Leave as pieces.
- So Compendium, Book and Leave stay reachable through the HUD pieces (catalog tab "App").
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 461d9f8. App._hud_shown hides the ViewBar while table_ui.hud.editor is open. Added a check to tools/test_minimal.gd. Tests: 57/57 green.
<!-- SECTION:FINAL_SUMMARY:END -->
