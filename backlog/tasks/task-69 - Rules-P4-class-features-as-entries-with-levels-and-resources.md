---
id: TASK-69
title: 'Rules P4: class features as entries with levels and resources'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:45'
updated_date: '2026-11-02 03:04'
labels:
  - rules
  - phase-4
  - data
dependencies:
  - TASK-64
  - TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
rules-automation.md, section 5.3. Class and subclass features are one Markdown text today, and the level table was lost (it was Dataview).
- Split them into feature entries `{name, class, subclass, level, text, uses, effects}` per heading.
- Recover the levels from the vault's class pages (level table) or with an AI pass as drafts.
- Class resources (Rage, Ki/Focus, Sorcery Points, Bardic Inspiration, Channel Divinity, Second Wind, Action Surge ...) with max per level and reset, from dragoon-core tables.
- Characters get their features automatically from `classes[]` + level, plus manual extras.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Class/subclass features are separate entries with level
- [x] #2 Class resources with per-level max and reset
- [x] #3 A character's features follow from classes and level
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices:
- Levels come from the class page's own level table (it survived in the description markdown; only the Dataview part was lost), else from the text ("Starting at 7th level"). Subclass features without a level (Tenets, Oath/Circle Spells) get the subclass's first level, marked level_guessed. Anything still at level 0 is listed but not given (warn, never block). The DM fixes it in the editor and sets `edited: true` so re-runs keep it.
- No AI pass was needed: 1492 features across all packages, 0 without a level.
- Features named like a dragoon-core class resource (Rage, Second Wind, Action Surge, Channel Divinity...) link to it via `resource` instead of their own uses, so nothing is counted twice. Indomitable was added to the core table (1/2/3 at 9/13/17).
- Granted features are added in sheet_for only, never stored. Dropping a feature on a sheet stores just the manual list.
- Package features are now visible to all sheet lookups via NetTable._features() (world + package class features).
- Effects for the new entries: run tools/parse_effects.gd -- --write again if wanted.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ClassFeatures (scripts/rules/class_features.gd): split / levels_from_table / level_from_text / granted / index_of. tools/split_class_features.gd (`-- [dir] --write --verbose`) writes kind:"class" feature entries {id, name, class, subclass, level, text, uses|resource} into each package's features.json (run on local data: 1492 features). NetTable._features() and class_features_of(sheet): sheets get their class and subclass features up to their level plus their own, shown by name (_refs) on the HUD and kept out of the stored list. Test: tools/test_class_features.gd (50/50 green). Commit 6943fd7.
<!-- SECTION:FINAL_SUMMARY:END -->
