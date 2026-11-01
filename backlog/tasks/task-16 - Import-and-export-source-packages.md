---
id: TASK-16
title: Import and export source packages
status: To Do
assignee: []
created_date: '2026-11-01 11:30'
labels:
  - data
dependencies:
  - TASK-15
documentation:
  - package-format
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Packages (one per source book) can be exported from and imported into the VTT as a single file, e.g. a zip of the package folder (manifest, JSON per kind, assets). Import checks format version and asks what to do if a package with the same id already exists.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Export writes one file per package including its assets
- [ ] #2 Import validates format and format_version and shows the manifest counts before installing
- [ ] #3 Existing package with the same id: choose replace, keep both or cancel
- [ ] #4 Packages can be enabled/disabled or removed in the VTT
<!-- AC:END -->
