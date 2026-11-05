---
id: TASK-103
title: >-
  Table Bunny 8: Tamago's chat window with a chat log per client (private DM
  requests)
status: Done
assignee: []
created_date: '2026-11-04 17:05'
updated_date: '2026-11-04 17:05'
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
- [x] #1 Clicking the bunny opens a Tamago-style chat window above it (also on the desktop), movable, with the log and a multi-line input
- [x] #2 Each client has its own log, kept locally per table and player; the DM's private questions never reach players and vice versa
- [x] #3 Private questions and answers are no longer in the table's chat; 'To everyone' answers are in the table's chat and the logs
- [x] #4 Tests pass
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit cc19528.

**BunnyChat** (`scripts/bunny/bunny_chat.gd`, a port of Tamago's ChatWindow) is a borderless window with the book cover look.
- It has a header to drag it anywhere, an X and Esc to close it.
- The log shows my entries on cards (right) and the bunny's on pages (left). Answers are rendered as Markdown, errors and busy hints are muted, "to everyone" is tagged. It loads 20 at a time and shows older ones when scrolled to the top.
- The input is multi-line: Enter sends, Shift+Enter starts a new line. It has a "To everyone" checkbox and a Send button.
- It is native (`force_native`) where the bunny walks on the desktop. Clicking the bunny opens it above the bunny; without a chat window it falls back to the table's chat with "/bunny ".
- The bunny listens (ears up) while something is typed in it.

**Logs** (NetTable):
- `bunny_log`: entries `{role user/bunny/error, text, public, mood, by, time}`, max 500.
- Saved in `user://bunny_chat/<world>-<timeline>-<dm|player>.json`. The host sends the table key with `bunny_look`.
- `_add_bunny_line` routes them:
  - my question → my log;
  - an answer → the log of whoever it is for;
  - only public ones also go to the table's chat feed.
- So the DM's private questions stay on the DM's computer. The `/bunny` command in the table's chat still works and lands in the log.

Checked on the desktop in a real run (screenshot): the window above the bunny, Markdown in answers, "to everyone" tags.

Tests: test_bunny_net:
- questions and answers in the log, not in the table's chat;
- public ones in both;
- the DM's question in the DM's log only;
- a separate file per player, saved on disk;
- the chat window renders the log and asks from it.
table_bunny, app, bunny_brain, bunny_mcp, bunny_tools and minimal pass.
<!-- SECTION:FINAL_SUMMARY:END -->
