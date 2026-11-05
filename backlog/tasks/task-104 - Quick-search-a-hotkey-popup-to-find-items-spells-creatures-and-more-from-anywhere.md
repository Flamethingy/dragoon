---
id: TASK-104
title: >-
  Quick search: a hotkey popup to find items, spells, creatures and more from
  anywhere
status: In Progress
assignee: []
created_date: '2026-11-04 17:42'
updated_date: '2026-11-05 00:52'
labels:
  - ui
  - compendium
  - search
dependencies: []
priority: medium
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-04: a quick search for items and other entries, without opening the Compendium first.

- **A hotkey** (e.g. Ctrl+K or Ctrl+Space, plus a small 🔍 button) opens a search field in the middle of the screen, like a command palette.
- **Search as you type** across all kinds: items, spells, creatures, features, classes, rules / conditions, plus characters and places of the world.
  - fuzzy matching; results grouped by kind, with an icon and source;
  - arrow keys plus Enter;
  - the existing index can help (`PackageDB.suggest` / the unified index).
- **Filters** with prefixes, e.g. `i:` items, `s:` spells, `c:` creatures, or kind chips.
- **Results:**
  - **Enter** opens the entry (card / Compendium tab);
  - results can be **dragged** straight onto the map / a token / a sheet (TASK-93 / 94);
  - **Shift+Enter** adds it to the active character (same rights as TASK-94).
- **Respects reveal and drafts:** players only find what they are allowed to see.
- Esc or a click outside closes it. The last searches are remembered.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Hotkey opens a search popup anywhere at the table; Esc closes it
- [ ] #2 Typing finds entries of all kinds (fuzzy), grouped, keyboard-navigable
- [ ] #3 Enter opens the entry; dragging a result works like dragging from the Book
- [ ] #4 Players only see revealed, non-draft entries
- [ ] #5 Headless test: query returns expected entries and respects reveal
<!-- AC:END -->
