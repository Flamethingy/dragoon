---
id: TASK-33
title: 'App shell: start screen with Host/Join, world and timeline picker'
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 15:52'
updated_date: '2026-11-01 16:18'
labels:
  - mvp
  - ui
dependencies:
  - TASK-32
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
One app instead of separate scenes. The start screen offers:
- **Host as DM:** pick a world and a timeline, or create them.
  - New world: name, calendar. This also creates the start timeline.
  - New timeline: fork from a timeline at a point, then set name, players and colours, and the DM colour.
- **Join as player:** address and player name.
- **Compendium** without a session.

Inside a session, the table, compendium, notes and timeline are switchable views (tabs or side bar). Uses the data model from TASK-32.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 App starts on the start screen (main scene) with Host as DM, Join as player and Compendium
- [x] #2 New world and new timeline (incl. fork point, players, colours) can be created there
- [x] #3 In a session the table, compendium, notes and timeline views can be switched without restarting
- [x] #4 The last used world/timeline is preselected
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
scenes/app.tscn (App) is the main scene. StartScreen: host as DM (world + timeline picker, New world with calendar, New timeline = NewTimelineForm with parent, fork point, players with colours, DM), join as player (name, address), compendium without a session. In a session a view bar switches Table / Compendium / Notes (NotesView) / Timeline (TimelineView, event list); players get Table and Notes; Leave goes back to the start screen. Last world/timeline/name/address/port kept in user://app.cfg. TableUI got `lobby` and `compendium_opener`. Test: tools/test_app.gd. Commit 38977f8.
<!-- SECTION:FINAL_SUMMARY:END -->
