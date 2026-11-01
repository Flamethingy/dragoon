---
id: TASK-38
title: 'Start screen: worlds panel with timelines, saved servers with heartbeat'
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 17:00'
updated_date: '2026-11-01 17:07'
labels:
  - ui
  - network
  - mvp
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Replace the "Host as DM" / "Join as player" choice:
- **Left: Worlds panel.** One card per world with image, name and short description (if written).
  - The world's timelines are listed in or under the card (name, session count, last played). **Clicking a timeline hosts it.**
  - Buttons: **New world**, **New timeline** (fork, per world), and edit world (opens world editing).
- **Middle: Servers panel.** Saved addresses (name, address, port) with a live status dot via a heartbeat.
  - The host answers a small status request on its port: world, timeline, DM name, players online.
  - Poll about every 10 s; show online, offline or a version mismatch.
  - **Clicking an online server joins it** (player name taken from the settings or asked once).
  - Buttons: **Add server**, edit, remove.
- The compendium stays reachable from the start screen.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Worlds panel with image/name/description cards and their timelines; clicking a timeline hosts it
- [x] #2 New world, new timeline and edit world are available there
- [x] #3 Servers panel with saved addresses and a heartbeat status (online/offline, world, players)
- [x] #4 Clicking an online server joins; servers can be added, edited and removed
- [x] #5 Saved servers persist in user://
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
StartScreen rebuilt. Worlds panel: a card per world (picture = its image or first world map, name, description) with one button per timeline (name, fork of, sessions, last played); a click hosts it on the port shown above. New world..., and per card New timeline... and Edit world. Servers panel: your name, Add server..., Check now; rows with a status dot (online / offline / other version) plus world, timeline, DM and players online, and Edit and × buttons. Clicking an online row joins, asking the name once if it is empty. Heartbeat: ServerStatus.Responder answers "DRAGOON STATUS <protocol>" over TCP on the same port number as the ENet game (UDP); Probe polls without blocking, every 10 s and when the screen is shown. Servers are saved in user://servers.json. Tests in tools/test_app.gd; screenshot via tools/screenshot_start.gd. Commit 40205c2.
<!-- SECTION:FINAL_SUMMARY:END -->
