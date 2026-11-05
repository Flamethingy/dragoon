---
id: TASK-101
title: >-
  Table Bunny 6: Tamago's bunny rig, animations, smoke puff and customizable
  look
status: Done
assignee: []
created_date: '2026-11-04 16:21'
updated_date: '2026-11-04 16:28'
labels:
  - ai
  - bunny
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico (2026-11-04) wants the whole bunny animation system from Tamago in the VTT, adapted to Dragoon. From now on new bunny features are built in Tamago and in Dragoon at the same time.

Port from `D:\Godot\tamago`:
- `scripts/pet/rig.gd` → BunnyRig: atlas parts on bones, poses blended, blinking, talking mouth, landing squash, swing when carried.
- `shaders/recolor.gdshader` → colour slots.
- `scripts/fx/puff.gd` + `SmokePuff.png` → appear and vanish in a puff.
- the behaviour of `scripts/pet/tamago.gd`: idle/walk timers, hops, dragging by the scruff, falling, landing.

Dragoon adaptation:
- the bunny walks along the bottom of the table window;
- it maps the host's state (thinking / working / sleeping) to poses;
- it listens while the chat holds "/bunny";
- the look and behaviour are set by the host and sent to every client;
- size and quiet stay per client.

The file mapping is in a doc so both projects stay in sync.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The Table Bunny uses Tamago's rig and art with all her poses (idle, walk, jump, fall, dragged, thinking, working, listening) plus a sleep pose, blinking, a talking mouth and a landing squash
- [x] #2 It appears and vanishes in a smoke puff (session start, shown/hidden, switched on/off)
- [x] #3 It can be picked up by the scruff, swings and falls back down when released; it hops now and then
- [x] #4 The host customizes its colours (fur, hair, inner ear, eyes) and behaviour (walk speed, idle/walk times, hop chance) in the Table Bunny settings with a live preview; every client sees the same bunny
- [x] #5 A doc maps the shared files between Tamago and Dragoon
- [x] #6 Tests pass
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 8e355e7.

Ported Tamago's bunny to Dragoon. The art, `rig.json`, `layout.json`, `SmokePuff.png` and `recolor.gdshader` are copied as they are.

**BunnyRig** (`scripts/bunny/bunny_rig.gd`) is Tamago's `rig.gd`:
- poses: idle, walk, jump, fall, dragged, thinking, working, listening;
- blinking, talking mouth, landing squash, pendulum swing when carried;
- recolouring per slot.

Dragoon additions are marked `Dragoon:`:
- a sleep pose (ears flat, eyes shut, slow breathing);
- `mood`: happy wags, sad/sleepy droop.

**BunnyPuff** is Tamago's `puff.gd`.

**TableBunny** was rebuilt on the rig, following Tamago's `tamago.gd` behaviour:
- idle and walk timers, random direction, turning at the edges;
- hops (`hop_chance`, `hop_height`);
- picked up by the scruff (neck to the cursor) and falls when let go; a click still opens the chat with "/bunny ";
- appears in a puff (session start, shown again, switched on) and vanishes in one (switched off, hidden);
- poses follow the host's state: thinking, working, sleep. It listens while "/bunny" is typed in the focused chat, and its mouth moves while it says something.

**Customization** is in Esc > Table Bunny:
- colour pickers for fur, hair, inner ear and eyes, with a live BunnyRig preview and an "As drawn" button;
- walk speed, rest and walk times, hop chance and height.

These are saved in the host's bunny settings (`colors`, `behaviour`). `NetTable.share_bunny_look()` and the RPC `bunny_look_set` send them to every client, also on join; clients sanitize them. Size, quiet and on/off stay per client.

The doc `bunny-shared-with-tamago.md` maps the files between the two projects and how to port changes. CREDITS and progress were updated.

Tests:
- `test_table_bunny` was extended: rig parts, puff in and out, sleep pose, walk pose, carry and neck, fall and land, hop, thinking pose, talking mouth, host look on both clients, settings pickers, preview and save.
- bunny_net, bunny_mcp, bunny_brain, bunny_tools, app, close_buttons and character_hud pass.
- Checked visually in a real window (screenshot).

Open: the source and licence of SmokePuff.png (taken from Tamago) are unknown; noted in CREDITS.
<!-- SECTION:FINAL_SUMMARY:END -->
