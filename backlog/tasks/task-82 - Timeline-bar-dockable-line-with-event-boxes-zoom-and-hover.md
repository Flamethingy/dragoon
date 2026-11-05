---
id: TASK-82
title: 'Timeline bar: dockable line with event boxes, zoom and hover'
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-02 13:31'
updated_date: '2026-11-02 13:51'
labels:
  - timeline
  - ui
  - feature
dependencies:
  - TASK-81
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The timeline bar from Nico's sketch (2026-11-02): a horizontal line with white boxes for the moments (TASK-81), a cursor (the triangle) and a "now" end.

- **Window behaviour like the chat:** a DockPanel docked at the top of the table by default; it can float over the table and pops out into its own window past the program's edge (the same as TASK-80).
- **Placement by in-world time** (WorldCalendar), with zoom (wheel) and pan (drag), so 6-second combat rounds and days of travel both fit. Dates and times show along the line depending on the zoom.
- **Colours per map**, so parallel scenes (two fights on two maps at the same time) can be told apart; a legend or tooltip names the map.
- **Session markers** (start/end, with real-world date and time).
- **Hover** over a box shows its change summary; a click moves the cursor there (see the scrubbing ticket).
- The old DM Timeline list view stays and can be opened from a box, showing that moment's events.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Bar docks at the top, floats and pops out like the chat (DockPanel)
- [x] #2 Boxes sit by in-world time; zoom and pan work; date/time labels adapt to the zoom
- [x] #3 Boxes are coloured by map; session start/end markers are shown
- [x] #4 Hovering a box shows its summary; clicking it sets the cursor
- [x] #5 A box can open the DM Timeline list filtered to that moment
- [x] #6 Headless test plus a screenshot check
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 8ca385c.
- TimelineBar is a DockPanel (section "timeline") docked at the top by default. DockPanel gains a "top" dock that pushes side docks down and returns the room when floated or hidden.
- TimelineLine draws:
  - white boxes by in-world seconds, with combat rounds tinted
  - map-colour strips
  - session bands with their real date
  - an orange "now" mark and the cursor triangle
- Wheel zooms around the mouse; Shift+wheel and right/middle drag pan; tick labels adapt from rounds to years.
- Hover shows the moment summary. Left click or drag scrubs, snapping to boxes; Now and Home return to the present. Right click (DM) opens the Timeline list filtered to that moment (Show all resets it).
- TimelineSync (host) builds the moments live and sends players a version without creatures on fogged maps; an undo triggers a rebuild.
- Tests: tools/test_timeline_bar.gd and screenshot tools/screenshot_timeline.gd; the full suite passes. The colours use the theme ink on the light panel.
<!-- SECTION:FINAL_SUMMARY:END -->
