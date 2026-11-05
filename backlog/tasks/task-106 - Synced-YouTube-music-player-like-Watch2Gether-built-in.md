---
id: TASK-106
title: 'Synced YouTube music player (like Watch2Gether, built in)'
status: In Planning
assignee: []
created_date: '2026-11-04 18:27'
labels:
  - audio
  - net
  - idea
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Idea, not planned yet. Details in [[doc-4]] (Idea: synced YouTube music player); on the wishlist in [[doc-2]].

- A WebView add-on (e.g. godot-wry) plays YouTube's official IFrame player.
- The host syncs `{video, playing, position, host_time}` over NetTable; late joiners catch up.
- Playlist / queue, volume per client, playlists per scene, and combat switching.
- **Do a spike first:** does a WebView run in Godot 4.7?
- Never download audio (YouTube's terms).
<!-- SECTION:DESCRIPTION:END -->
