---
id: TASK-112
title: >-
  Calendar instead of timeline on the main screen: track story time and travel,
  not every turn
status: Done
assignee: []
created_date: '2026-11-05 00:14'
updated_date: '2026-11-05 01:47'
labels:
  - timeline
  - calendar
  - ui
  - concept
dependencies: []
priority: medium
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-05: the timeline is too much right now. Move towards a **calendar view** that tracks **story-related time and travel** (days, journeys, rests, important events) instead of every single turn.

- **Main screen:** no longer the always-visible timeline bar. At most a small date display ("Day 12, Spring · Road to Red Fang"), and a click opens the calendar.
- **Calendar:** days/weeks of the world calendar (the package's `calendar`), with entries for travel ("3 days: Westmarch → Red Fang"), long rests, sessions and story events. The DM moves time forward in big steps (hours / days / travel).
- **Under the hood:** the event log stays as it is (undo, rewinding TASK-88). Only the display changes. Combat turns are no longer shown on the main screen.
- **Timeline view later:** the old view stays available as its own window (or comes back later), not on the main screen.

Open questions for Nico:
- Which calendar entries matter (travel, rests, sessions, notes)?
- Is travel just a time skip, or a route on the map?
- Can players see the calendar?
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Nico 2026-11-05 01:41:**
- "We'll add them one by one, just get the calendar view running for now."
- Travel will be a route on the map, but time can also pass without moving.
- Everyone can see the calendar, but not all entries.
- TASK-113: remove the timeline (bar) from the main screen for now; he'll come back to it later.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit after 6463217 (TASK-112).

- **Main screen:**
  - The timeline bar is hidden (`TableUI.SHOW_TIMELINE_BAR := false`). Its code and the looking back stay, so it can come back.
  - Today's date sits at the top centre ("📅 Fireday, 5. Deepwinter 1 AF, 10:00"); a click opens the calendar.
- **CalendarView** (scripts/ui/calendar_view.gd, its own window per TASK-113):
  - One month of the world's calendar: weekday header, the 1st on its weekday, festival months without the week grid. Today is marked; ‹ › and Today navigate.
  - Entries on their days, coloured by kind: sessions (the first event of each session), time passing (`time.advanced` with a reason; travel = reason containing "travel", shown on its first day with its length), long rests (one per day). Combat steps (round / turn / combat) are left out. Tooltip per day.
  - The DM row "Pass time": +1 hour, +8 hours (long rest), +1 day, N days + reason → `advance_clock`.
- **Visibility:** everyone sees the calendar. Players get today and their entries from the host (`NetTable.calendar_for(player)`, `request_calendar`, `calendar_received`, re-asked when the timeline changes). Events with `data.hidden` / `data.dm_only` are left out for them.
- **Tests:** tools/test_calendar_view.gd, all good. test_timeline_bar, test_look_back, test_app, test_net_table, test_character_hud, test_dock and test_calendar are still green. Real-run screenshot: tools/screenshot_calendar.gd.
- **Next, one by one:**
  - more entry kinds (notes, story events, DM-only entries set by hand);
  - travel as a route on the map;
  - a journey drawn across its days;
  - the old timeline view coming back later.
<!-- SECTION:FINAL_SUMMARY:END -->
