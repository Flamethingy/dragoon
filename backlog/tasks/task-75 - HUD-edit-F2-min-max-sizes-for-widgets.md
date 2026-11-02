---
id: TASK-75
title: 'HUD edit (F2): min/max sizes for widgets'
status: To Do
assignee: []
created_date: '2026-11-02 01:16'
labels:
  - hud
  - ui
  - feedback
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico's feedback 2026-11-02: in F2 edit mode some HUD elements take up far more space than they need. Each widget type needs a sensible minimum size and a default/maximum size that fits its content, so widgets don't spread out and resizing can't make them tiny or huge.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every widget type has a min size and a content-fitting default size
- [ ] #2 Resizing in F2 respects the min size
- [ ] #3 Existing layouts load and get clamped
<!-- AC:END -->
