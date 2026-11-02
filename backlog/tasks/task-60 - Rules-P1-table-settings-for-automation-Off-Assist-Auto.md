---
id: TASK-60
title: 'Rules P1: table settings for automation (Off / Assist / Auto)'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
updated_date: '2026-11-02 01:17'
labels:
  - rules
  - phase-1
  - ui
dependencies:
  - TASK-53
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
One small settings page per world (DM only). Each category can be Off / Assist / Auto: damage, healing, conditions, durations, resources/slots, concentration, death saves, movement warnings, reaction hints.
- **Defaults per Nico's decision:** Auto for damage, conditions, resources, durations and concentration prompts; reaction hints Off.
- The house rules (crit rule) and the edition from TASK-53 live on the same page.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Settings page with Off/Assist/Auto per category, stored with the world
- [x] #2 Rules features read their category setting
- [x] #3 Defaults as decided
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design decisions (Mochi):
- Meaning of the levels: Off = the table does nothing, the DM does it by hand; Assist = the result is posted in the feed with an Apply for the DM; Auto = applied right away (undo / rewind corrects it).
- Defaults: Auto for damage, healing, conditions, durations, resources/slots, concentration, death saves (decision 1); movement warnings = Assist (it only ever warns, never blocks); reaction hints = Off.
- Stored in the world's package.json under rules.automation; unknown values fall back to the default.
- Access: a "Rules" view (DM only) in the app, a window on the calm table; a "Rules" app button on the default HUD (players never see it). Existing custom HUD layouts can add it from the builder's App tab.
- AC 2: the read path is Rules.automation(settings, cat) / NetTable.automation(cat); the P1 features (54 damage, 55 saves, 56 conditions, 57 death saves, 59 concentration, 49 slots) read their category as they are built.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 185734e. Rules.AUTOMATION (9 categories, defaults as decided) with Rules.automation() / NetTable.automation(). New RulesView (scripts/rules/rules_view.gd): edition, house rules (crit, flanking) and an Off/Assist/Auto pick per category, saved into the world at once and sent to players with the table. App view "rules" (DM), Rules button on the default HUD. Tests: test_rules (defaults, overrides, junk), test_app (page, saving), HUD/minimal tests updated; 34 suites green.
<!-- SECTION:FINAL_SUMMARY:END -->
