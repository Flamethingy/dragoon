---
title: Bunny shared with Tamago
type: other
created_date: '2026-11-04'
---
# The bunny, shared with Tamago

The Table Bunny (TASK-98, TASK-101) has the same body and ways as Tamago's desktop bunnies
(`D:\Godot\tamago`). From now on, new bunny features are built in **both projects at the same
time**. This page lists which file belongs with which, and what Dragoon does differently.

## Files

| Tamago | Dragoon | What |
|---|---|---|
| `assets/characters/tamago/atlas.png`, `rig.json`, `layout.json` | `assets/bunny/` (same names) | The art: parts, bones layout, colour palette. Copy them over again when the art changes (`tools/import_character.py` in Tamago). |
| `assets/Images/SmokePuff.png` | `assets/bunny/SmokePuff.png` | The smoke puff, a 3x3 sheet. |
| `shaders/recolor.gdshader` | `shaders/recolor.gdshader` | Recolouring per colour slot. Identical. |
| `scripts/pet/rig.gd` (`TamagoRig`) | `scripts/bunny/bunny_rig.gd` (`BunnyRig`) | The rig, poses, blinking, talking mouth, squash and swing. The same code except for the lines marked `Dragoon:`. |
| `scripts/fx/puff.gd` (`Puff`) | `scripts/bunny/bunny_puff.gd` (`BunnyPuff`) | The puff. Waits 1 frame instead of 2: Dragoon has no desktop window shape to update. |
| `scripts/pet/tamago.gd` (`Tamago`) | `scripts/bunny/table_bunny.gd` (`TableBunny`), "Moving" and "Input" | Behaviour: idle and walk timers, turning at the edges, hops, carrying by the scruff, falling and landing. |
| `scripts/pet/screen_world.gd` (`ScreenWorld`) | `scripts/bunny/bunny_desk.gd` (`BunnyDesk`) | The see-through, always-on-top window over a screen's usable area, the click-through region and the platforms. One window, on the screen Dragoon is on. The only platform is Dragoon's own window top, because there's no service to list the other windows. |
| `assets/characters/tamago/icon.png` | `assets/bunny/icon.png` | The icon. In Dragoon it's the button in the lower left corner, recoloured like the tray icon. |
| `scripts/ui/chat_window.gd` (`ChatWindow`) | `scripts/bunny/bunny_chat.gd` (`BunnyChat`) | The chat window: borderless, above the bunny, dragged by its header, the log paged, a multi-line input. In Dragoon it adds "To everyone", has no attachments, and keeps the log locally per table and player (`NetTable.bunny_log`) instead of the service's history. |
| `scripts/pet/bunny.gd` (`Bunny`), "Puffs" | `table_bunny.gd`, "Puffs" | `appear()` and `vanish()` in a puff. |
| Profile `look.colors` and `behaviour` (service `profiles.py`, dashboard "Look" tab) | `BunnyBrain` settings `colors` and `behaviour`, set in `BunnySettings` (Esc > Table Bunny) | Customization. In Dragoon the host sets it and `NetTable.bunny_look` sends it to every client. |

## What Dragoon does differently

- **Where it walks** (TASK-102):
  - Along the taskbar in its own desktop window (BunnyDesk), like Tamago.
  - It can jump up onto Dragoon's window top and ride along with it.
  - With nothing to jump onto, it hops in place (`hop_chance`, `hop_height`).
  - Where see-through windows aren't available (headless, tests), or when the player picks "Stay inside Dragoon", it walks along the bottom of Dragoon's window instead.
- **States.** The host's brain state picks the pose:
  - thinking → `thinking`;
  - working → `working`;
  - no brain → `sleep`, a new pose with ears flat and eyes shut.
  - It also listens (`listening`) while someone types "/bunny" in a focused chat.
- **Moods.** An answer's mood (happy / sad / sleepy) changes the pose: a wagging tail, or drooping ears and half-shut eyes.
- **Per client.** On/off, quiet and small/big (`user://bunny_client.cfg`). Look and behaviour are the same for everyone.
- **Bubbles.** Dragoon's own speech bubble (UISkin page) and a status badge, instead of Tamago's TravelBook bubbles and thought icons.

## Porting a change

1. Make the change in one project.
2. Copy it to the matching file above. Keep the `Dragoon:` lines, and keep the class names
   (`BunnyRig`, `BunnyPuff`) and paths (`res://assets/bunny/`).
3. Run `tools/test_table_bunny.gd` in Dragoon.
