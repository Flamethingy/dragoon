---
id: TASK-119
title: >-
  Group fan: members glide back to the lower right quickly as soon as the mouse
  leaves
status: To Do
assignee: []
created_date: '2026-11-05 03:03'
updated_date: '2026-11-05 03:03'
labels:
  - map
  - tokens
  - polish
dependencies:
  - TASK-116
priority: high
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-05, polish for the group fan (`GroupStack`, TASK-116):

- As soon as the mouse **leaves the group token** (and isn't over the fan), the fanned members move **back to the lower right edge** of the main token, with **no long wait**.
- **Short smoothing path:** each member glides back on a short eased path (ease-out, ~0.12–0.18 s; slightly staggered is fine). Quick, not sluggish, and no snapping.
- Opening the fan can use the same smoothing (in reverse), so it feels consistent.
- Keep just enough grace time (~0.1 s, instead of 0.3 s) that moving the mouse from the token into the fan doesn't close it. If the mouse comes back during the glide, it turns around smoothly.
- A member that is being dragged out (`MemberDrag`) is not affected.

Update tools/test_group_tokens.gd (closes quickly after leaving, ends at the stack positions).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Leaving the group token (not into the fan) sends the members back to the lower right within ~0.2 s
- [ ] #2 The way back is a short eased glide, not a snap
- [ ] #3 Moving into the fan still works (short grace); coming back mid-glide reverses smoothly
- [ ] #4 test_group_tokens updated and green
<!-- AC:END -->
