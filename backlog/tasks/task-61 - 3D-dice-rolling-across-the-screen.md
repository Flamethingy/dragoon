---
id: TASK-61
title: 3D dice rolling across the screen
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:44'
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
- [ ] #1 All rolls animate as 3D dice for all clients, landing on the host's results
- [ ] #2 Account colours, hidden rolls only for the DM
- [ ] #3 Crit effect
- [ ] #4 Settings for on/off, speed and linger time
<!-- AC:END -->
