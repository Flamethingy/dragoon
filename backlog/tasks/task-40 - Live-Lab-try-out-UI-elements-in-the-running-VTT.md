---
id: TASK-40
title: 'Live Lab: try out UI elements in the running VTT'
status: To Do
assignee: []
created_date: '2026-11-01 17:37'
labels:
  - dev-tools
  - later
dependencies:
  - TASK-37
  - TASK-38
  - TASK-39
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
For the brainstorm session with Nico, Tamago and Mochi after TASK-37/38/39. Not started until then.

A dev-only autoload `LiveLab`, in debug builds only:
- Listens on a localhost port.
- Takes GDScript snippets, compiles them at runtime (`GDScript.new()`, `source_code`, `reload()`) and runs them in the game.
- Results go onto a "Lab" CanvasLayer above the UI that can be cleared with one key.

Together with the godot-ai game tools (UI tree, input, screenshots), this lets us spawn and tweak panels, themes and windows live and see them right away. Whatever we like gets built properly afterwards.
<!-- SECTION:DESCRIPTION:END -->
