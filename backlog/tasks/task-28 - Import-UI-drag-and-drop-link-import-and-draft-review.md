---
id: TASK-28
title: 'Import UI: drag and drop, link import and draft review'
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 14:26'
updated_date: '2026-11-01 14:45'
labels:
  - import
  - ui
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
VTT side (Mochi), see import-agent.md. Drag & drop of PDF/image files onto the window and an "Import from link" button in the Packages menu; pick target package; start tools/import_agent.py as a process and show its progress log. Draft review screen: entry next to its source page, edit fields, crop editor for the image, accept/discard per entry and "accept all"; merge into the package with duplicate handling (replace, keep both, skip). Settings field for the Anthropic API key (stored locally only).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Dropping a PDF or image starts an import into the chosen package
- [x] #2 A link can be imported from the Packages menu
- [x] #3 Drafts show side by side with their source page and can be edited, cropped, accepted or discarded
- [x] #4 Accepted drafts appear in the compendium; duplicates ask what to do
- [x] #5 API key is entered in settings and kept out of packages and git
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Nico (2026-11-01): Mochi takes this after finishing his current work. Data side is TASK-27 (Tamago).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit e60addb.
- `scripts/import/`:
  - ImportJobs: starts the agent with the API key only in its environment (`ANTHROPIC_API_KEY`). Settings are kept in `user://import_settings.cfg`. It follows `data/imports/<job>/` (status, log, dead process = failed, cancel), crops the picture and merges drafts (features and picture come along, origin is kept, a read-only target is unlocked, replace / keep both / skip).
  - ImportPanel: file or link, target or a new world package, API key and Python settings, jobs with a live log.
  - DraftReview: the editor on the draft beside its source page with drag-to-crop; Accept / Discard / Accept all.
- Compendium: dropping a PDF or image opens the import window prefilled; Start runs it. The Packages window has "Import from link...". Merges reload the book.
- The contract for TASK-27 is appended to import-agent.md. `tools/fake_import_agent.py` follows it.
- Test: `tools/test_import_ui.gd`; all 22 suites pass.
- Real imports need Tamago's `tools/import_agent.py` (TASK-27).
<!-- SECTION:FINAL_SUMMARY:END -->
