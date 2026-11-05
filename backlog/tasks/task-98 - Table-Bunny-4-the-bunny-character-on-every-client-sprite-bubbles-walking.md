---
id: TASK-98
title: 'Table Bunny 4: the bunny character on every client (sprite, bubbles, walking)'
status: Done
assignee: []
created_date: '2026-11-04 14:30'
updated_date: '2026-11-04 15:07'
labels:
  - ai
  - bunny
  - ui
  - art
dependencies:
  - TASK-97
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**On hold until Nico approves the design: [[doc-3]] Table Bunny design** (open question: in the Dragoon window or on the taskbar).

v1 lives in the Dragoon window:
- the bunny walks along the bottom edge or above the HUD;
- animations: idle, walk, talk, think, sleep;
- speech bubbles for answers, with longer answers in a small panel;
- clicking it opens the chat box;
- the mood comes from the answer.

Per-client settings: on/off, mute, small/big.

Sprites to be decided: our own, or made with PixelLab.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The bunny shows on every client and reacts to its own answers
- [x] #2 Click opens the chat; bubbles show answers
- [x] #3 Can be turned off / resized per client
- [x] #4 Sleeps when the host has no brain
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Nico 2026-11-04: on every client, the bunny shows the shared status (TASK-97): a thinking / working animation, a small status bubble or badge ("thinking for Borin", "importing… 40%", "2 waiting"), and the same status in the chat box.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit fdcaf66.

**`TableBunny`** (`scripts/bunny/table_bunny.gd`): TableUI puts one on every client's table (v1: inside the Dragoon window, at the bottom edge).

- **Look:** a placeholder drawn in code (no sprites yet).
  - A white bunny with ears, eyes, nose and mouth.
  - Animations: idle (breathing), walk (hops and walks to random spots along the bottom), talk (mouth moves, bounce), think (three blinking dots), work (a turning ring), sleep (closed eyes, ears down, z/Z).
  - Its face follows the answer's mood: happy (^^), sad, sleepy, neutral.
- **Status (TASK-97, Nico's note):** it follows `NetTable.bunny_state` on every client: think / work / sleep. A badge over its head shows "thinking for Borin", "importing Deep Magic 40%" or "2 waiting". The chat line shows the same.
- **Answers:** `bunny_message` → a speech bubble over it, kept inside the window.
  - Answers over 180 characters get a small scrolling panel.
  - The bubble goes after a few seconds, or on a click.
  - "In line" hints use the thinking face.
- **Click:** opens the chat with "/bunny " typed and focused. **Right click:** ask / quiet / big–small / hide.
- **Per client** (`user://bunny_client.cfg`):
  - on/off (hidden; the Esc menu "Show the bunny" brings it back);
  - quiet: no bubbles, chat only. "Mute" means this for now, since the bunny has no sounds yet;
  - small (56 px) / big (88 px).
- **No brain:** it sleeps.
- **Test:** `tools/test_table_bunny.gd`.
  - App: the bunny is at the bottom and asleep; big, hidden and back via the Esc menu; it walks.
  - DM + Bob, each with a bunny and a fake brain: both wake; both think, with the badge; Bob's bunny talks in a bubble (happy), the DM's doesn't; a long answer scrolls; quiet gives no bubble but the chat line; a click opens the chat with /bunny; asleep again without a key.
  - app, minimal, bunny_net, close_buttons and character_hud pass.

**Open for Nico:**
1. Real sprites: our own, or PixelLab (costs credits, so I haven't spent any).
2. The taskbar variant (doc-3, option 2) for later.
<!-- SECTION:FINAL_SUMMARY:END -->
