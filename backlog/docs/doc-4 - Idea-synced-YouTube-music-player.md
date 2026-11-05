---
id: doc-4
title: 'Idea: synced YouTube music player'
type: other
tags:
  - idea
  - audio
  - later
project: Dragoon
created_date: '2026-11-04 17:33'
updated_date: '2026-11-04 17:33'
---

# Idea: synced YouTube music player (later)

Nico 2026-11-04: we use Watch2Gether for background music right now. A player built into Dragoon that keeps YouTube in sync for everyone. Also on the wishlist: [[doc-2]] "YouTube music player (like w2g, but better)".

## How it could work
- **Playback:** a WebView add-on (e.g. *godot-wry*, using the WebView2 already on Windows) runs YouTube's official **IFrame player**, hidden or as a small player window.
- **Sync:** the DM (or whoever is allowed) sends `{video, playing, position, host_time}` over NetTable.
  - Every client works out the target position and seeks if it's off by more than 1–2 s.
  - Late joiners get the current state.
- **Playlist / queue:** paste links, reorder, loop, shuffle. Volume per client, plus mute.
- **VTT extra:** playlists per scene or map ("Combat", "Tavern"), with fading; combat start switches to the battle playlist.

## Watch out for
- Only the official player: downloading audio (yt-dlp) breaks YouTube's terms.
- Ads and age gates per client. Sync has to wait for them.
- WebView add-ons in Godot 4.7 aren't tested much, so **do a spike first**.
- Alternative or addition: local music files from the package, sent by the host (offline, legally simpler).

## Possible tickets
1. Spike: WebView add-on plus the YouTube IFrame player in Godot 4.7
2. Sync over NetTable (play / pause / seek / late join)
3. Player window: playlist, queue, volume per client
4. Scene playlists and combat switching
