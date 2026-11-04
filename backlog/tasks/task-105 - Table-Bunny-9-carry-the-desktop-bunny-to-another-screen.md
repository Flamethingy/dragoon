---
id: TASK-105
title: 'Table Bunny 9: carry the desktop bunny to another screen'
status: In Progress
assignee: []
created_date: '2026-11-04 17:56'
labels:
  - ai
  - bunny
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico (2026-11-04): it's fine that it only walks on the taskbar, but it should be possible to pull it to other screens.

How it works:
- While the bunny is carried with the mouse, BunnyDesk follows the real cursor (Tamago does the same). When the cursor moves over another screen, the desk window moves to that screen with the bunny under the cursor.
- The chosen screen is saved per client (TableBunny setting "screen"). The desk then stops following Dragoon's window until "Back to Dragoon's screen" is picked in the bunny's menu.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Carrying the bunny over another screen moves it there, under the cursor; let go it falls to that screen's taskbar
- [ ] #2 It stays on that screen (saved per client) even when Dragoon's window is elsewhere
- [ ] #3 Its menu has 'Back to Dragoon's screen'
- [ ] #4 Tests pass
<!-- AC:END -->
