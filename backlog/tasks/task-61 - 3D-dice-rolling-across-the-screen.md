---
id: TASK-61
title: 3D dice rolling across the screen
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
updated_date: '2026-11-02 01:58'
labels:
  - dice
  - ui
  - phase-1
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico's group never uses physical dice and loves 3D dice rolling down the screen.
- Every roll shows physically simulated 3D dice (Jolt physics, d4 to d20 plus d100 as two d10) tumbling over the table view, for everyone in the session.
- **The host's result stays authoritative:** the dice are animated to land on the rolled faces. Either simulate first and map the faces, or nudge them at the end, but never reroll on the client.
- Dice colour = the roller's account colour. Hidden DM rolls are only shown to the DM.
- Crits get a little effect (glow/sparkle).
- Settings: on/off, speed, and how long dice stay visible.
- Manual entry ("I rolled: __") only in a small menu (Nico: no physical dice).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All rolls animate as 3D dice for all clients, landing on the host's results
- [x] #2 Account colours, hidden rolls only for the DM
- [x] #3 Crit effect
- [x] #4 Settings for on/off, speed and linger time
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design decisions (Mochi):
- Landing on the host's result: "nudge at the end" variant without moving the die: the numbers on the faces are swapped (once while it slows down, where the tumble hides it, once more when it rests). Physics stays real, nothing is rerolled on a client.
- Each client simulates its own dice (positions differ between screens, the numbers don't).
- The tray only throws for new roll cards in my feed (hidden DM rolls never reach players, so they only see their own); a new roll clears the previous dice. At most 24 dice per roll.
- d100 = a tens die (00-90, slightly darker) + a units die (0-9).
- Settings are per computer (user://dice.cfg), in the chat's small "Dice" menu: 3D dice on/off, fast (1.6x), stay 2/4/8 s. Default: on, normal, 3 s.
- Manual entry sits in the same menu ("Enter a roll by hand…" → a chat line "rolled by hand: 17"), per Nico's decision 2.
- Headless runs (tests, servers) throw no dice unless DiceTray.force.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit c04cb6c. scripts/dice/die_shapes.gd (all polyhedra), die_3d.gd (RigidBody3D die, face relabelling to the host's value, crit glow), dice_tray.gd (transparent SubViewport overlay with walls, throw per roll card in the account colour, linger/clear, settings). NetTable.roll_shown signal; TableUI adds the tray; ChatBox Dice menu with settings and a manual roll. New suite tools/test_dice3d.gd (shapes, d100 split, physics lands on values, settings, table hookup, manual roll); verified visually with a rendered screenshot. 41 suites green.
<!-- SECTION:FINAL_SUMMARY:END -->
