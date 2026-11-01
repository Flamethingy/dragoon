---
id: TASK-11
title: Send NPC or world into the active campaign
status: Done
assignee: []
created_date: '2026-11-01 11:17'
updated_date: '2026-11-01 13:58'
labels:
  - mvp
  - data
dependencies:
  - TASK-6
documentation:
  - Dragoon Concept
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MVP (concept: Campaign layers): the DM sends a single core/world entity or a whole world into the active campaign. This creates a campaign copy that remembers its origin and then drifts freely. Pulling later upstream changes is a separate, deliberate action (not in MVP).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 DM can send one entity or a whole world folder into the campaign
- [x] #2 The campaign copy stores its origin (layer + path)
- [x] #3 Changing the core/world original does not change the campaign copy
- [x] #4 Two campaigns can hold different versions of the same character
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
EntryStore.send / send_world copy core/world entries (with features, images, origin) into the campaign and log entity.sent; existing ids are skipped on world sends. Copies are independent of the original; two campaigns hold different versions. Compendium: "Send to campaign" on core/world entries, "Send world..." on the cover. Test tools/test_send.gd; commit 6b6d702.
<!-- SECTION:FINAL_SUMMARY:END -->
