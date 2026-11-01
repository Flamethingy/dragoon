---
id: TASK-19
title: '"Visible for" popup and colored frames'
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-01 12:58'
updated_date: '2026-11-01 13:51'
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
- [x] #1 Every account (players and DM) can pick a color; it is saved and sent to all clients
- [x] #2 Selecting text shows a 'Visible for' popup; applying creates or edits a reveal tag with a stable id
- [x] #3 Changing visibility during a session writes a reveal.changed event
- [x] #4 Hidden passages show a frame in the account color(s); several people = mixed/striped frame; passages visible to all have no frame
- [x] #5 Hover hint: 'Only you and Lena can see this'
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Frames: Markdown.to_bbcode draws reveal passages and %% %% in the account colors of the people who may see them. Inline passages get a tinted background (several people: mixed color). Block passages get nested bordered cells, one ring per person. Party passages have no frame. Hovering shows "Only you and Ann can see this". RevealPopup (scripts/ui/reveal_popup.gd) has a checkbox per player in their color, Party, DM only, and Apply / Visible to all. It opens when you select text with the mouse, or press Ctrl+H, in the editor's Markdown fields and the table's note input. Reveal.apply wraps the selection or edits the existing passage, with stable ids from Reveal.next_id. In a campaign during a session, changing an existing passage writes reveal.changed (add/remove compared with the current viewers) and leaves the text alone. Account colors: Campaign.accounts() and set_color() read and write campaign.json. The table's top bar has a color button: NetTable.set_my_color -> the DM saves it -> receive_accounts goes to every client (also on join). Tests: tools/test_reveal_ui.gd and tools/test_net_table.gd. Commit 2336ac2.
<!-- SECTION:FINAL_SUMMARY:END -->
