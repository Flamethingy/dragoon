---
id: TASK-109
title: >-
  Sheet lists: double-click the name opens the entry view, a click on the
  picture uses it
status: In Progress
assignee: []
created_date: '2026-11-04 23:20'
labels:
  - sheets
  - hud
dependencies:
  - TASK-107
  - TASK-108
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-04: "It should open on a double click on the text of skill or item in a character editor... on icon click you can do use action".

In the Inventory / Spells / Features pieces (TASK-107), on the HUD and on the sheet pages:
- double-clicking the name / text opens the entry's view (TASK-108: fields, chips, On Use, text) in a small window;
- clicking the picture (icon) uses the item or casts the spell;
- a single click on the text does nothing any more.

Players get the view as they may see it: package entries are read locally, the timeline's own entries are asked from the host (NetTable.open_entry, reveals apply).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Clicking the icon in a list row or a card uses the item / casts the spell; clicking the text doesn't
- [ ] #2 Double-clicking a row or card opens a window with the entry's view including On Use
- [ ] #3 Features open their view too; players get timeline entries through the host
- [ ] #4 Tests pass
<!-- AC:END -->
