---
id: TASK-14
title: Session notes with real and in-world date
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-01 11:18'
updated_date: '2026-11-01 12:29'
labels:
  - mvp
  - notes
dependencies:
  - TASK-2
documentation:
  - Dragoon Concept
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MVP (concept: Chronicle and shared notes): session notes stored as markdown in the campaign, each entry carrying the real date, session number and in-world date. Live co-editing comes later.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 DM and players can write notes during a session
- [x] #2 Each entry shows real date, session number and in-world date (formatted by the calendar)
- [x] #3 Notes are saved as markdown in the campaign folder
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
SessionNotes (scripts/notes/session_notes.gd): one markdown file per session in <campaign>/notes (session-NN.md, prep.md for session 0) with frontmatter; each entry = HTML comment with its data + "### real · Session N · in-world moment · writer" heading + markdown text, parsed back on open. NetTable: players send notes to the DM (RPC), the DM stamps them with EventLog's clock and session, saves and broadcasts; joiners get a sync; DM "Next session" button starts a new session (event) and notes file. Notes panel on the right.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SessionNotes (scripts/notes/session_notes.gd) writes one markdown file per session to <campaign>/notes/session-NN.md (prep.md for notes between sessions), with frontmatter (session, started). Each entry has a heading "real date time · Session N · in-world moment (WorldCalendar.format_moment) · writer", then the markdown text. An HTML comment above the heading holds the data, so entries can be read back; Obsidian hides it. The network table has a notes panel on the right (markdown rendered, Ctrl+Enter adds a note). Players send notes to the DM, who stamps them with the event log's clock and session, saves them and shares them with everyone. Joining players get every note of the current session. The DM's "Next session" button logs session.started and opens a new notes file. Tests: tools/test_session_notes.gd and extended tools/test_net_table.gd. Screenshot: tools/screenshot_notes.gd. Live co-editing comes later, per the description. Player names arrive with the lobby (TASK-8); until then notes show "Player <id>".
<!-- SECTION:FINAL_SUMMARY:END -->
