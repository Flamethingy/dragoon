---
id: TASK-19
title: '"Visible for" popup and colored frames'
status: To Do
assignee: []
created_date: '2026-11-01 12:58'
labels:
  - mvp
  - ui
dependencies:
  - TASK-18
documentation:
  - reveal-visibility
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
UI side of [[reveal-visibility]]: select text in any Markdown editor/view and a small "Visible for" popup appears (checkboxes per player, Party, DM only). Applying wraps or edits a `<reveal>` tag; during a session it writes a `reveal.changed` event. Hidden passages get a colored frame in the color each person picked for **their account**, including the DM (no fixed red). Accounts therefore need a color setting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every account (players and DM) can pick a color; it is saved and sent to all clients
- [ ] #2 Selecting text shows a 'Visible for' popup; applying creates or edits a reveal tag with a stable id
- [ ] #3 Changing visibility during a session writes a reveal.changed event
- [ ] #4 Hidden passages show a frame in the account color(s); several people = mixed/striped frame; passages visible to all have no frame
- [ ] #5 Hover hint: 'Only you and Lena can see this'
<!-- AC:END -->
