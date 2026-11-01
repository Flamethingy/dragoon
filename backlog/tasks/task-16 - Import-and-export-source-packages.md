---
id: TASK-16
title: Import and export source packages
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-01 11:30'
updated_date: '2026-11-01 12:27'
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
- [x] #1 Export writes one file per package including its assets
- [x] #2 Import validates format and format_version and shows the manifest counts before installing
- [x] #3 Existing package with the same id: choose replace, keep both or cancel
- [x] #4 Packages can be enabled/disabled or removed in the VTT
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
PackageManager (scripts/compendium/package_manager.gd): export a package folder as one zip file (.dragoonpkg) with assets; inspect a file (format, format_version, id, counts, safe paths); install with replace / keep both (new id) ; enable/disable (user://packages.cfg, PackageDB skips disabled); remove = move to data/removed (recoverable). Packages window in the compendium (list, toggles, export, remove, import with confirmation dialog). Headless test on a temp root.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PackageManager (scripts/compendium/package_manager.gd) exports a package folder, including its assets, as a single .dragoonpkg zip. Before installing, inspect() checks the format, format_version (up to 1), the id and that paths are safe, and reads the manifest counts. install() takes replace, keep both (new id like <id>-2 with "(2)" in the name) or cancel. It unpacks into a temp folder first, and a replaced copy goes to data/removed. Enable/disable is stored per packages folder in user://packages.cfg, and PackageDB skips disabled packages. remove() moves the folder to data/removed. UI: a "Packages..." button in the compendium opens PackagesPanel (on/off, Export..., Remove with confirmation, Import... showing name, version and counts, plus a conflict choice); the book reloads on close. tools/test_packages.gd passes. Screenshot: tools/screenshot_packages.gd.
<!-- SECTION:FINAL_SUMMARY:END -->
