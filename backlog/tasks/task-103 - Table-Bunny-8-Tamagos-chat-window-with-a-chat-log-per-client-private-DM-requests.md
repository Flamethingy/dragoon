---
id: TASK-103
title: >-
  Table Bunny 8: Tamago's chat window with a chat log per client (private DM
  requests)
status: In Progress
assignee: []
created_date: '2026-11-04 17:05'
labels:
  - ai
  - bunny
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico (2026-11-04): the bunny chat should be like Tamago's chat, not the game chat, with a chat log for each client, so the DM can ask for things the players shouldn't necessarily see.

How it works:
- BunnyChat is Tamago's ChatWindow for Dragoon: a borderless window above the bunny (native on the desktop) that you can drag by its header. It shows my log, paged, and has a multi-line input (Enter sends, Shift+Enter makes a new line), a "To everyone" option and Esc/X to close.
- Each client keeps its own log in user://bunny_chat/<world>-<timeline>-<player>.json.
- Private questions and answers go into the asker's log only.
- Public ones also go into the table's chat for everyone.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Clicking the bunny opens a Tamago-style chat window above it (also on the desktop), movable, with the log and a multi-line input
- [ ] #2 Each client has its own log, kept locally per table and player; the DM's private questions never reach players and vice versa
- [ ] #3 Private questions and answers are no longer in the table's chat; 'To everyone' answers are in the table's chat and the logs
- [ ] #4 Tests pass
<!-- AC:END -->
