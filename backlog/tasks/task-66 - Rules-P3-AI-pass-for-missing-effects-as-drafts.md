---
id: TASK-66
title: 'Rules P3: AI pass for missing effects (as drafts)'
status: To Do
assignee:
  - Mochi
created_date: '2026-11-02 00:45'
labels:
  - rules
  - phase-3
  - import
dependencies:
  - TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
For entries the regex parser can't structure: a batch run of the import agent (Claude, Batch API for half the price) proposes `effects` per entry against the format. Results land as drafts of the change, and the DM reviews and publishes them on the Drafts page (diff view: old vs proposed effects).

Do one package at a time with a cost estimate shown first. Start with the 5e core rules spells.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Batch run proposes effects for unparsed entries with a cost estimate first
- [ ] #2 Proposals are reviewable drafts with a diff; publishing writes them
- [ ] #3 Run on 5e-core-rules spells
<!-- AC:END -->
